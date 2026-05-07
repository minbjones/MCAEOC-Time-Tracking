from contextlib import contextmanager
from pathlib import Path

import pyodbc

from config import settings


_MOBILE_FACE_SCHEMA_READY = False


def _mobile_face_migration_path() -> Path:
    return Path(__file__).resolve().parents[1] / "sql" / "mobile_face_migration.sql"


def _split_sql_batches(script_text: str):
    batch = []
    for line in script_text.splitlines():
        if line.strip().upper() == "GO":
            statement = "\n".join(batch).strip()
            if statement:
                yield statement
            batch = []
            continue
        batch.append(line)

    statement = "\n".join(batch).strip()
    if statement:
        yield statement


def ensure_mobile_face_schema(connection):
    global _MOBILE_FACE_SCHEMA_READY
    if _MOBILE_FACE_SCHEMA_READY:
        return

    migration_path = _mobile_face_migration_path()
    script_text = migration_path.read_text(encoding="utf-8")
    cursor = connection.cursor()
    for statement in _split_sql_batches(script_text):
        cursor.execute(statement)
    connection.commit()
    _MOBILE_FACE_SCHEMA_READY = True


@contextmanager
def get_db():
    connection = pyodbc.connect(settings.sql_connection_string)
    try:
        ensure_mobile_face_schema(connection)
        yield connection
    finally:
        connection.close()
