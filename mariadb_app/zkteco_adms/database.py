from contextlib import contextmanager
from pathlib import Path
import sys


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import pyodbc  # noqa: E402

from config import settings  # noqa: E402


_ADMS_SCHEMA_READY = False


def ensure_adms_schema(connection):
    global _ADMS_SCHEMA_READY
    if _ADMS_SCHEMA_READY:
        return

    cursor = connection.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS dbo.AdmsRequestLogs
        (
            AdmsRequestLogId INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            RequestPath VARCHAR(200) NOT NULL,
            HttpMethod VARCHAR(10) NOT NULL,
            DeviceIdentifier VARCHAR(200) NULL,
            RemoteAddress VARCHAR(100) NULL,
            QueryString LONGTEXT NULL,
            HeadersJson LONGTEXT NULL,
            BodyText LONGTEXT NULL,
            ParsedRecordCount INT NOT NULL DEFAULT 0,
            ImportedRecordCount INT NOT NULL DEFAULT 0,
            ImportStatus VARCHAR(20) NOT NULL DEFAULT 'Pending',
            FailureReason VARCHAR(500) NULL,
            CreatedAt DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
            UpdatedAt DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6)
        ) ENGINE=InnoDB
        """
    )
    connection.commit()
    _ADMS_SCHEMA_READY = True


@contextmanager
def get_db():
    connection = pyodbc.connect(settings.mariadb_connection_string)
    try:
        ensure_adms_schema(connection)
        yield connection
    finally:
        connection.close()
