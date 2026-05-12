import os
import re
from types import SimpleNamespace
from urllib.parse import parse_qsl

import pymysql


Error = pymysql.MySQLError
ProgrammingError = pymysql.ProgrammingError
InterfaceError = pymysql.InterfaceError


def _parse_connection_string(conn_str: str) -> dict:
    parts = {}
    for chunk in conn_str.split(";"):
        if not chunk.strip() or "=" not in chunk:
            continue
        key, value = chunk.split("=", 1)
        parts[key.strip().lower()] = value.strip()
    return parts


def _namespace_row(row_dict):
    if row_dict is None:
        return None
    return SimpleNamespace(**row_dict)


def _translate_exec(sql: str) -> str:
    match = re.match(r"^\s*EXEC\s+([A-Za-z0-9_\.]+)\s+(.*)$", sql.strip(), re.IGNORECASE | re.DOTALL)
    if not match:
        return sql
    proc_name = match.group(1)
    args = match.group(2)
    placeholder_count = args.count("?")
    return f"CALL {proc_name}({', '.join(['%s'] * placeholder_count)})"


def _translate_top(sql: str) -> str:
    match = re.search(r"SELECT\s+TOP\s+(\d+)\s", sql, re.IGNORECASE)
    if not match:
        return sql
    limit = match.group(1)
    sql = re.sub(r"SELECT\s+TOP\s+\d+\s", "SELECT ", sql, count=1, flags=re.IGNORECASE)
    if re.search(r"\bLIMIT\b", sql, re.IGNORECASE):
        return sql
    return sql.rstrip().rstrip(";") + f" LIMIT {limit}"


def _translate_sql(sql: str) -> str:
    translated = sql
    translated = translated.replace("SELECT @@SERVERNAME AS ServerName, DB_NAME() AS DatabaseName", "SELECT @@hostname AS ServerName, DATABASE() AS DatabaseName")
    translated = re.sub(r"\bISNULL\s*\(", "IFNULL(", translated, flags=re.IGNORECASE)
    translated = re.sub(r"\bSYSUTCDATETIME\s*\(\s*\)", "UTC_TIMESTAMP(6)", translated, flags=re.IGNORECASE)
    translated = re.sub(
        r"DATEDIFF\s*\(\s*MINUTE\s*,\s*([^,]+?)\s*,\s*([^)]+?)\s*\)",
        r"TIMESTAMPDIFF(MINUTE, \1, \2)",
        translated,
        flags=re.IGNORECASE,
    )
    translated = re.sub(r"\bWITH\s+EmployeeTree\s+AS\b", "WITH RECURSIVE EmployeeTree AS", translated, flags=re.IGNORECASE)
    translated = re.sub(r"\bOUTER\s+APPLY\s*\(", "LEFT JOIN LATERAL (", translated, flags=re.IGNORECASE)
    translated = re.sub(r"\bCROSS\s+APPLY\s*\(", "JOIN LATERAL (", translated, flags=re.IGNORECASE)
    translated = _translate_exec(translated)
    translated = _translate_top(translated)
    translated = translated.replace("?", "%s")
    return translated


class CursorWrapper:
    def __init__(self, cursor):
        self._cursor = cursor

    @property
    def lastrowid(self):
        return self._cursor.lastrowid

    @property
    def rowcount(self):
        return self._cursor.rowcount

    def execute(self, sql, *params):
        translated = _translate_sql(sql)
        flattened = params
        if len(params) == 1 and isinstance(params[0], (list, tuple)):
            flattened = tuple(params[0])
        self._cursor.execute(translated, flattened)
        return self

    def executemany(self, sql, seq_of_params):
        translated = _translate_sql(sql)
        self._cursor.executemany(translated, seq_of_params)
        return self

    def fetchone(self):
        return _namespace_row(self._cursor.fetchone())

    def fetchall(self):
        return [_namespace_row(row) for row in self._cursor.fetchall()]

    def __iter__(self):
        for row in self._cursor:
            yield _namespace_row(row)


class ConnectionWrapper:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self):
        return CursorWrapper(self._connection.cursor())

    def commit(self):
        return self._connection.commit()

    def rollback(self):
        return self._connection.rollback()

    def close(self):
        return self._connection.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type:
            self.rollback()
        self.close()


def connect(conn_str: str):
    config = _parse_connection_string(conn_str)
    host = config.get("server") or config.get("host") or os.getenv("MYSQL_HOST", "mariadb")
    if host.startswith("tcp:"):
        host = host[4:]
    if "," in host:
        host, port_from_host = host.split(",", 1)
        config.setdefault("port", port_from_host)
    database = config.get("database") or os.getenv("MYSQL_DATABASE", "dbo")
    user = config.get("uid") or config.get("user") or os.getenv("MYSQL_USER", "mcaeoc")
    password = config.get("pwd") or config.get("password") or os.getenv("MYSQL_PASSWORD", "mcaeocpass")
    port = int(config.get("port") or os.getenv("MYSQL_PORT", "3306"))

    connection = pymysql.connect(
        host=host,
        user=user,
        password=password,
        database=database,
        port=port,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
    )
    return ConnectionWrapper(connection)
