from contextlib import contextmanager
from pathlib import Path
import sys


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import pyodbc  # noqa: E402

from config import settings  # noqa: E402


_MOBILE_FACE_SCHEMA_READY = False


def ensure_mobile_face_schema(connection):
    global _MOBILE_FACE_SCHEMA_READY
    if _MOBILE_FACE_SCHEMA_READY:
        return

    cursor = connection.cursor()
    statements = [
        """
        CREATE TABLE IF NOT EXISTS dbo.MobileDevices
        (
            MobileDeviceId INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            EmployeeId INT NOT NULL,
            DeviceIdentifier VARCHAR(200) NOT NULL UNIQUE,
            DeviceName VARCHAR(200) NULL,
            Platform VARCHAR(30) NOT NULL DEFAULT 'Android',
            RegisteredAt DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
            LastSeenAt DATETIME(6) NULL,
            IsActive TINYINT(1) NOT NULL DEFAULT 1,
            CONSTRAINT FK_MobileDevices_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId)
        ) ENGINE=InnoDB
        """,
        """
        CREATE TABLE IF NOT EXISTS dbo.FaceTemplates
        (
            FaceTemplateId INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            EmployeeId INT NOT NULL,
            ModelName VARCHAR(50) NOT NULL,
            DetectorBackend VARCHAR(50) NOT NULL,
            TemplateVersion VARCHAR(50) NOT NULL,
            EmbeddingJson LONGTEXT NOT NULL,
            EmbeddingDimensions INT NOT NULL,
            EnrolledAt DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
            EnrolledByEmployeeId INT NULL,
            IsActive TINYINT(1) NOT NULL DEFAULT 1,
            Notes VARCHAR(500) NULL,
            CONSTRAINT FK_FaceTemplates_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
            CONSTRAINT FK_FaceTemplates_EnrolledBy FOREIGN KEY (EnrolledByEmployeeId) REFERENCES dbo.Employees(EmployeeId)
        ) ENGINE=InnoDB
        """,
        """
        CREATE TABLE IF NOT EXISTS dbo.FaceVerificationAttempts
        (
            FaceVerificationAttemptId INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            EmployeeId INT NULL,
            DeviceIdentifier VARCHAR(200) NOT NULL,
            VerificationPurpose VARCHAR(30) NOT NULL,
            VerificationStatus VARCHAR(20) NOT NULL,
            ConfidenceScore DECIMAL(8,4) NULL,
            DistanceScore DECIMAL(8,4) NULL,
            FailureReason VARCHAR(500) NULL,
            CapturedAt DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
            CONSTRAINT FK_FaceVerificationAttempts_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId)
        ) ENGINE=InnoDB
        """,
    ]
    for statement in statements:
        cursor.execute(statement)
    connection.commit()
    _MOBILE_FACE_SCHEMA_READY = True


@contextmanager
def get_db():
    connection = pyodbc.connect(settings.mariadb_connection_string)
    try:
        ensure_mobile_face_schema(connection)
        yield connection
    finally:
        connection.close()
