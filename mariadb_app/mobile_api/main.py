import json
from typing import List

from fastapi import Depends, FastAPI, Header, HTTPException

from config import settings
from database import get_db
from face_service import OpenSourceFaceService
from models import (
    ApiResponse,
    DeviceRegistrationRequest,
    EmployeeListItem,
    FaceClockRequest,
    FaceClockResponse,
    FaceEnrollmentRequest,
    IdentifyClockRequest,
    LoginRequest,
    LoginResponse,
)
from security import decode_b64, hash_password, is_valid_api_key


app = FastAPI(title=settings.api_title)
face_service = OpenSourceFaceService()


def require_api_key(x_api_key: str = Header(...)):
    if not is_valid_api_key(x_api_key):
        raise HTTPException(status_code=401, detail="Invalid API key.")


def decode_face_image_or_400(encoded_image: str, field_label: str) -> bytes:
    try:
        return decode_b64(encoded_image)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"{field_label} is not valid base64 image data.") from exc


def create_embedding_or_400(image_bytes: bytes, field_label: str) -> list[float]:
    try:
        return face_service.represent(image_bytes)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"{field_label}: {str(exc).strip()}") from exc


def register_or_update_device(cursor, employee_id: int, device_identifier: str, device_name: str | None, platform: str):
    cursor.execute(
        """
        SELECT MobileDeviceId
        FROM dbo.MobileDevices
        WHERE DeviceIdentifier = ?
        LIMIT 1
        """,
        device_identifier,
    )
    existing = cursor.fetchone()
    if existing:
        cursor.execute(
            """
            UPDATE dbo.MobileDevices
            SET EmployeeId = ?,
                DeviceName = ?,
                Platform = ?,
                LastSeenAt = UTC_TIMESTAMP(6),
                IsActive = 1
            WHERE MobileDeviceId = ?
            """,
            employee_id,
            device_name,
            platform,
            existing.MobileDeviceId,
        )
    else:
        cursor.execute(
            """
            INSERT INTO dbo.MobileDevices
            (
                EmployeeId,
                DeviceIdentifier,
                DeviceName,
                Platform,
                LastSeenAt,
                IsActive
            )
            VALUES
            (
                ?, ?, ?, ?, UTC_TIMESTAMP(6), 1
            )
            """,
            employee_id,
            device_identifier,
            device_name,
            platform,
        )


def record_verification_attempt(cursor, employee_id, device_identifier: str, purpose: str, status: str, confidence: float, distance: float, failure_reason: str | None):
    cursor.execute(
        """
        INSERT INTO dbo.FaceVerificationAttempts
        (
            EmployeeId,
            DeviceIdentifier,
            VerificationPurpose,
            VerificationStatus,
            ConfidenceScore,
            DistanceScore,
            FailureReason
        )
        VALUES
        (
            ?, ?, ?, ?, ?, ?, ?
        )
        """,
        employee_id,
        device_identifier,
        purpose,
        status,
        confidence,
        distance,
        failure_reason,
    )


def apply_mobile_clock_event(cursor, employee_id: int, event_type: str, device_identifier: str, latitude, longitude):
    location_note = None
    if latitude is not None and longitude is not None:
        location_note = f"Lat {latitude}, Lon {longitude}"

    if event_type == "ClockIn":
        cursor.execute(
            """
            SELECT TimeEntryId
            FROM dbo.TimeEntries
            WHERE EmployeeId = ?
              AND ClockOutTime IS NULL
            ORDER BY ClockInTime DESC, TimeEntryId DESC
            LIMIT 1
            """,
            employee_id,
        )
        if cursor.fetchone():
            raise HTTPException(status_code=400, detail="Employee is already clocked in.")

        cursor.execute(
            """
            INSERT INTO dbo.TimeEntries
            (
                EmployeeId,
                ClockInTime,
                Notes,
                EntrySource
            )
            VALUES
            (
                ?, UTC_TIMESTAMP(6), ?, 'Mobile'
            )
            """,
            employee_id,
            location_note or f"Mobile clock-in from {device_identifier}",
        )
        return

    cursor.execute(
        """
        SELECT TimeEntryId
        FROM dbo.TimeEntries
        WHERE EmployeeId = ?
          AND ClockOutTime IS NULL
        ORDER BY ClockInTime DESC, TimeEntryId DESC
        LIMIT 1
        """,
        employee_id,
    )
    open_entry = cursor.fetchone()
    if not open_entry:
        raise HTTPException(status_code=400, detail="Employee is not currently clocked in.")

    cursor.execute(
        """
        UPDATE dbo.TimeEntries
        SET ClockOutTime = UTC_TIMESTAMP(6),
            Notes = COALESCE(Notes, ?)
        WHERE TimeEntryId = ?
        """,
        location_note or f"Mobile clock-out from {device_identifier}",
        open_entry.TimeEntryId,
    )


@app.get("/health")
def health_check():
    db_ok = False
    employees_table = False
    face_templates_table = False
    db_error = None

    try:
        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM information_schema.tables
                        WHERE table_schema = DATABASE() AND table_name = 'Employees'
                    ) THEN 1 ELSE 0 END AS HasEmployees,
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM information_schema.tables
                        WHERE table_schema = DATABASE() AND table_name = 'FaceTemplates'
                    ) THEN 1 ELSE 0 END AS HasFaceTemplates
                """
            )
            row = cursor.fetchone()
            db_ok = True
            employees_table = bool(row.HasEmployees)
            face_templates_table = bool(row.HasFaceTemplates)
    except Exception as error:
        db_error = str(error)

    return {
        "status": "ok",
        "engine": "MariaDB",
        "faceProvider": "DeepFace",
        "databaseConnected": db_ok,
        "employeesTablePresent": employees_table,
        "faceTemplatesTablePresent": face_templates_table,
        "databaseError": db_error,
    }


@app.get("/api/mobile/employees", response_model=List[EmployeeListItem], dependencies=[Depends(require_api_key)])
def list_active_employees():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                E.EmployeeId AS EmployeeId,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                R.RoleName,
                CASE WHEN EXISTS
                (
                    SELECT 1 FROM dbo.FaceTemplates FT
                    WHERE FT.EmployeeId = E.EmployeeId AND FT.IsActive = 1
                ) THEN 1 ELSE 0 END AS HasFaceTemplate
            FROM dbo.Employees E
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            WHERE E.IsActive = 'Yes'
            ORDER BY E.LastName, E.FirstName
            """
        )
        rows = cursor.fetchall()

    return [
        EmployeeListItem(
            employee_id=row.EmployeeId,
            full_name=row.FullName,
            role_name=row.RoleName,
            has_face_template=bool(row.HasFaceTemplate),
        )
        for row in rows
    ]


@app.post("/api/mobile/auth/login", response_model=LoginResponse, dependencies=[Depends(require_api_key)])
def mobile_login(payload: LoginRequest):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                E.EmployeeId,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                E.PasswordSalt,
                E.PasswordHash,
                R.RoleName,
                CASE WHEN EXISTS
                (
                    SELECT 1 FROM dbo.FaceTemplates FT
                    WHERE FT.EmployeeId = E.EmployeeId AND FT.IsActive = 1
                ) THEN 1 ELSE 0 END AS HasFaceTemplate
            FROM dbo.Employees E
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            WHERE LOWER(E.Email) = ? AND E.IsActive = 'Yes'
            LIMIT 1
            """,
            payload.email.strip().lower(),
        )
        user = cursor.fetchone()
        if not user or hash_password(user.PasswordSalt, payload.password) != user.PasswordHash:
            raise HTTPException(status_code=401, detail="Invalid email or password.")

        register_or_update_device(cursor, user.EmployeeId, payload.device_identifier, payload.device_name, "Android")
        conn.commit()

    return LoginResponse(
        success=True,
        message="Login successful.",
        employee_id=user.EmployeeId,
        full_name=user.FullName,
        role_name=user.RoleName,
        has_face_template=bool(user.HasFaceTemplate),
    )


@app.post("/api/mobile/devices/register", response_model=ApiResponse, dependencies=[Depends(require_api_key)])
def register_device(payload: DeviceRegistrationRequest):
    with get_db() as conn:
        cursor = conn.cursor()
        register_or_update_device(cursor, payload.employee_id, payload.device_identifier, payload.device_name, payload.platform)
        conn.commit()
    return ApiResponse(success=True, message="Device registered.")


@app.post("/api/mobile/face/enroll", response_model=ApiResponse, dependencies=[Depends(require_api_key)])
def enroll_face(payload: FaceEnrollmentRequest):
    image_bytes = decode_face_image_or_400(payload.face_template_b64, "Enrollment image")
    embedding = create_embedding_or_400(image_bytes, "Enrollment image")

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT LTRIM(RTRIM(CONCAT(FirstName, ' ', LastName))) AS FullName
            FROM dbo.Employees
            WHERE EmployeeId = ?
            LIMIT 1
            """,
            payload.employee_id,
        )
        employee = cursor.fetchone()
        if not employee:
            raise HTTPException(status_code=404, detail="Employee not found.")

        register_or_update_device(
            cursor,
            payload.employee_id,
            f"enroll-{payload.employee_id}",
            "Android Enrollment",
            "Android",
        )
        cursor.execute(
            """
            UPDATE dbo.FaceTemplates
            SET IsActive = 0
            WHERE EmployeeId = ? AND IsActive = 1
            """,
            payload.employee_id,
        )
        cursor.execute(
            """
            INSERT INTO dbo.FaceTemplates
            (
                EmployeeId,
                ModelName,
                DetectorBackend,
                TemplateVersion,
                EmbeddingJson,
                EmbeddingDimensions,
                EnrolledByEmployeeId,
                Notes
            )
            VALUES
            (
                ?, ?, ?, ?, ?, ?, ?, ?
            )
            """,
            payload.employee_id,
            settings.face_model_name,
            settings.face_detector_backend,
            payload.template_version,
            face_service.embedding_to_json(embedding),
            len(embedding),
            payload.employee_id,
            payload.notes,
        )
        conn.commit()

    return ApiResponse(success=True, message=f"Face template enrolled for {employee.FullName}.")


@app.post("/api/mobile/clock/verify-and-clock", response_model=FaceClockResponse, dependencies=[Depends(require_api_key)])
def verify_and_clock(payload: FaceClockRequest):
    selfie_bytes = decode_face_image_or_400(payload.selfie_image_b64, "Verification image")
    probe_embedding = create_embedding_or_400(selfie_bytes, "Verification image")

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                FT.EmbeddingJson,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName
            FROM dbo.FaceTemplates FT
            INNER JOIN dbo.Employees E ON E.EmployeeId = FT.EmployeeId
            WHERE FT.EmployeeId = ?
              AND FT.IsActive = 1
            ORDER BY FT.EnrolledAt DESC
            LIMIT 1
            """,
            payload.employee_id,
        )
        template_row = cursor.fetchone()
        if not template_row:
            raise HTTPException(status_code=400, detail="Employee has no active face enrollment.")

        stored_embedding = face_service.embedding_from_json(template_row.EmbeddingJson)
        matched, confidence_score, distance = face_service.compare(probe_embedding, stored_embedding)
        verification_status = "Passed" if matched else "Failed"
        failure_reason = None if matched else "Open-source face verification did not meet the configured threshold."

        record_verification_attempt(
            cursor,
            payload.employee_id,
            payload.device_identifier,
            payload.event_type,
            verification_status,
            confidence_score,
            distance,
            failure_reason,
        )

        if not matched:
            conn.commit()
            return FaceClockResponse(
                success=False,
                message="Face verification failed.",
                employee_id=payload.employee_id,
                full_name=template_row.FullName,
                event_type=payload.event_type,
                verification_status=verification_status,
                confidence_score=confidence_score,
                liveness_score=0.0,
            )

        register_or_update_device(
            cursor,
            payload.employee_id,
            payload.device_identifier,
            "Android Kiosk",
            "Android",
        )
        apply_mobile_clock_event(cursor, payload.employee_id, payload.event_type, payload.device_identifier, payload.latitude, payload.longitude)
        conn.commit()

    return FaceClockResponse(
        success=True,
        message=f"{payload.event_type} recorded.",
        employee_id=payload.employee_id,
        full_name=template_row.FullName,
        event_type=payload.event_type,
        verification_status="Passed",
        confidence_score=confidence_score,
        liveness_score=0.0,
    )


@app.post("/api/mobile/clock/identify-and-clock", response_model=FaceClockResponse, dependencies=[Depends(require_api_key)])
def identify_and_clock(payload: IdentifyClockRequest):
    selfie_bytes = decode_face_image_or_400(payload.selfie_image_b64, "Identification image")
    probe_embedding = create_embedding_or_400(selfie_bytes, "Identification image")

    best_match = None

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                FT.EmployeeId,
                FT.EmbeddingJson,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName
            FROM dbo.FaceTemplates FT
            INNER JOIN dbo.Employees E ON E.EmployeeId = FT.EmployeeId
            WHERE FT.IsActive = 1
              AND E.IsActive = 'Yes'
            """
        )
        rows = cursor.fetchall()
        for row in rows:
            stored_embedding = face_service.embedding_from_json(row.EmbeddingJson)
            matched, confidence_score, distance = face_service.compare(probe_embedding, stored_embedding)
            if not matched:
                continue
            candidate = {
                "employee_id": row.EmployeeId,
                "full_name": row.FullName,
                "confidence_score": confidence_score,
                "distance": distance,
            }
            if best_match is None or candidate["distance"] < best_match["distance"]:
                best_match = candidate

        if best_match is None:
            record_verification_attempt(
                cursor,
                None,
                payload.device_identifier,
                "Identify",
                "Failed",
                0.0,
                1.0,
                "No enrolled employee matched this face.",
            )
            conn.commit()
            return FaceClockResponse(
                success=False,
                message="No enrolled employee matched this face.",
                employee_id=None,
                full_name=None,
                event_type=None,
                verification_status="Failed",
                confidence_score=0.0,
                liveness_score=0.0,
            )

        cursor.execute(
            """
            SELECT
                CASE
                    WHEN EXISTS
                    (
                        SELECT 1
                        FROM dbo.TimeEntries T
                        WHERE T.EmployeeId = ?
                          AND T.ClockOutTime IS NULL
                    ) THEN 'ClockOut'
                    ELSE 'ClockIn'
                END AS NextEventType
            """,
            best_match["employee_id"],
        )
        event_row = cursor.fetchone()
        event_type = event_row.NextEventType

        register_or_update_device(
            cursor,
            best_match["employee_id"],
            payload.device_identifier,
            "Android Kiosk",
            "Android",
        )
        record_verification_attempt(
            cursor,
            best_match["employee_id"],
            payload.device_identifier,
            event_type,
            "Passed",
            best_match["confidence_score"],
            best_match["distance"],
            None,
        )
        apply_mobile_clock_event(cursor, best_match["employee_id"], event_type, payload.device_identifier, payload.latitude, payload.longitude)
        conn.commit()

    return FaceClockResponse(
        success=True,
        message=f"{event_type} recorded.",
        employee_id=best_match["employee_id"],
        full_name=best_match["full_name"],
        event_type=event_type,
        verification_status="Passed",
        confidence_score=best_match["confidence_score"],
        liveness_score=0.0,
    )
