from typing import List

import pyodbc
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


def next_event_type_for_employee(cursor, employee_id: int) -> str:
    cursor.execute(
        """
        SELECT CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.TimeEntries T
                WHERE T.PayrollId = ?
                  AND T.ClockOutTime IS NULL
            ) THEN 'ClockOut'
            ELSE 'ClockIn'
        END AS NextEventType
        """,
        employee_id,
    )
    row = cursor.fetchone()
    return row.NextEventType if row else "ClockIn"


def provider_reference_label() -> str:
    return f"{settings.face_model_name}:{settings.face_detector_backend}"


def record_verification_attempt(
    cursor,
    employee_id,
    device_identifier: str,
    verification_purpose: str,
    verification_status: str,
    confidence_score: float,
    liveness_score: float,
    distance_score,
    failure_reason,
    provider_reference,
):
    cursor.execute(
        """
        EXEC dbo.usp_RecordFaceVerificationAttempt
            @EmployeeId = ?,
            @DeviceIdentifier = ?,
            @VerificationPurpose = ?,
            @VerificationStatus = ?,
            @ConfidenceScore = ?,
            @LivenessScore = ?,
            @DistanceScore = ?,
            @FailureReason = ?,
            @ProviderReference = ?
        """,
        employee_id,
        device_identifier,
        verification_purpose,
        verification_status,
        confidence_score,
        liveness_score,
        distance_score,
        failure_reason,
        provider_reference,
    )
    return cursor.fetchone()


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
                    CASE WHEN OBJECT_ID('dbo.Employees', 'U') IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS HasEmployees,
                    CASE WHEN OBJECT_ID('dbo.FaceTemplates', 'U') IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS HasFaceTemplates
                """
            )
            row = cursor.fetchone()
            db_ok = True
            employees_table = bool(row.HasEmployees)
            face_templates_table = bool(row.HasFaceTemplates)
    except pyodbc.Error as error:
        db_error = str(error)

    return {
        "status": "ok",
        "faceProvider": "DeepFace",
        "faceModel": settings.face_model_name,
        "databaseConnected": db_ok,
        "employeesTablePresent": employees_table,
        "faceTemplatesTablePresent": face_templates_table,
        "databaseError": db_error,
    }


@app.get("/api/mobile/employees", response_model=List[EmployeeListItem], dependencies=[Depends(require_api_key)])
def list_active_employees():
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    E.PayrollId AS EmployeeId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    R.RoleName,
                    CASE WHEN EXISTS
                    (
                        SELECT 1 FROM dbo.FaceTemplates FT
                        WHERE FT.PayrollId = E.PayrollId AND FT.IsActive = 1
                    ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS HasFaceTemplate
                FROM dbo.Employees E
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                WHERE E.IsActive = 'Yes'
                ORDER BY E.LastName, E.FirstName
                """
            )
            rows = cursor.fetchall()
    except pyodbc.Error as error:
        raise HTTPException(status_code=500, detail=f"Database query failed: {error}")

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
                E.PayrollId AS EmployeeId,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                E.PasswordSalt,
                E.PasswordHash,
                R.RoleName,
                CASE WHEN EXISTS
                (
                    SELECT 1 FROM dbo.FaceTemplates FT
                    WHERE FT.PayrollId = E.PayrollId AND FT.IsActive = 1
                ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS HasFaceTemplate
            FROM dbo.Employees E
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            WHERE E.Email = ? AND E.IsActive = 'Yes'
            """,
            payload.email.strip().lower(),
        )
        user = cursor.fetchone()
        if not user or hash_password(user.PasswordSalt, payload.password) != user.PasswordHash:
            raise HTTPException(status_code=401, detail="Invalid email or password.")

        cursor.execute(
            """
            EXEC dbo.usp_RegisterMobileDevice
                @EmployeeId = ?,
                @DeviceIdentifier = ?,
                @DeviceName = ?,
                @Platform = 'Android'
            """,
            user.EmployeeId,
            payload.device_identifier,
            payload.device_name,
        )
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
        cursor.execute(
            """
            EXEC dbo.usp_RegisterMobileDevice
                @EmployeeId = ?,
                @DeviceIdentifier = ?,
                @DeviceName = ?,
                @Platform = ?
            """,
            payload.employee_id,
            payload.device_identifier,
            payload.device_name,
            payload.platform,
        )
        conn.commit()

    return ApiResponse(success=True, message="Device registered.")


@app.post("/api/mobile/face/enroll", response_model=ApiResponse, dependencies=[Depends(require_api_key)])
def enroll_face(payload: FaceEnrollmentRequest):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT LTRIM(RTRIM(CONCAT(FirstName, ' ', LastName))) AS FullName
            FROM dbo.Employees
            WHERE PayrollId = ?
            """,
            payload.employee_id,
        )
        employee = cursor.fetchone()
        if not employee:
            raise HTTPException(status_code=404, detail="Employee not found.")

        template_bytes = decode_b64(payload.face_template_b64)
        try:
            embedding = face_service.represent(template_bytes)
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error))

        cursor.execute(
            """
            UPDATE dbo.FaceTemplates
            SET IsActive = 0
            WHERE PayrollId = ? AND IsActive = 1
            """,
            payload.employee_id,
        )
        cursor.execute(
            """
            INSERT INTO dbo.FaceTemplates
            (
                PayrollId,
                ProviderName,
                TemplateVersion,
                TemplateData,
                EmbeddingJson,
                EmbeddingDimensions,
                ModelName,
                DetectorBackend,
                EnrolledByPayrollId,
                Notes
            )
            VALUES (?, 'DeepFace', ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            payload.employee_id,
            payload.template_version,
            template_bytes,
            face_service.embedding_to_json(embedding),
            len(embedding),
            settings.face_model_name,
            settings.face_detector_backend,
            payload.employee_id,
            payload.notes,
        )
        conn.commit()

    return ApiResponse(success=True, message="Face template enrolled.")


@app.post("/api/mobile/clock/verify-and-clock", response_model=FaceClockResponse, dependencies=[Depends(require_api_key)])
def verify_and_clock(payload: FaceClockRequest):
    selfie_bytes = decode_b64(payload.selfie_image_b64)

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT TOP 1 EmbeddingJson
            FROM dbo.FaceTemplates
            WHERE PayrollId = ? AND IsActive = 1
            ORDER BY EnrolledAt DESC
            """,
            payload.employee_id,
        )
        template_row = cursor.fetchone()
        if not template_row or not template_row.EmbeddingJson:
            record_verification_attempt(
                cursor,
                payload.employee_id,
                payload.device_identifier,
                payload.event_type,
                "Failed",
                0.0,
                1.0,
                None,
                "Employee has no active face enrollment.",
                provider_reference_label(),
            )
            conn.commit()
            raise HTTPException(status_code=400, detail="Employee has no active face enrollment.")

        try:
            probe_embedding = face_service.represent(selfie_bytes)
        except ValueError as error:
            record_verification_attempt(
                cursor,
                payload.employee_id,
                payload.device_identifier,
                payload.event_type,
                "Failed",
                0.0,
                1.0,
                None,
                str(error),
                provider_reference_label(),
            )
            conn.commit()
            raise HTTPException(status_code=400, detail=str(error))

        stored_embedding = face_service.embedding_from_json(template_row.EmbeddingJson)
        verification_passed, confidence_score, distance_score = face_service.compare(probe_embedding, stored_embedding)
        verification_status = "Passed" if verification_passed else "Failed"
        liveness_score = 1.0

        verification_attempt_row = record_verification_attempt(
            cursor,
            payload.employee_id,
            payload.device_identifier,
            payload.event_type,
            verification_status,
            confidence_score,
            liveness_score,
            distance_score,
            None if verification_passed else "DeepFace comparison did not meet the configured threshold.",
            provider_reference_label(),
        )
        verification_attempt_id = int(verification_attempt_row.FaceVerificationAttemptId)

        if not verification_passed:
            conn.commit()
            return FaceClockResponse(
                success=False,
                message="Face verification failed.",
                verification_status=verification_status,
                confidence_score=confidence_score,
                liveness_score=liveness_score,
            )

        cursor.execute(
            """
            EXEC dbo.usp_MobileClockEvent
                @EmployeeId = ?,
                @EventType = ?,
                @DeviceIdentifier = ?,
                @VerificationAttemptId = ?,
                @Latitude = ?,
                @Longitude = ?
            """,
            payload.employee_id,
            payload.event_type,
            payload.device_identifier,
            verification_attempt_id,
            payload.latitude,
            payload.longitude,
        )
        conn.commit()

    return FaceClockResponse(
        success=True,
        message=f"{payload.event_type} recorded.",
        employee_id=payload.employee_id,
        full_name=None,
        event_type=payload.event_type,
        verification_status=verification_status,
        confidence_score=confidence_score,
        liveness_score=liveness_score,
    )


@app.post("/api/mobile/clock/identify-and-clock", response_model=FaceClockResponse, dependencies=[Depends(require_api_key)])
def identify_and_clock(payload: IdentifyClockRequest):
    selfie_bytes = decode_b64(payload.selfie_image_b64)

    try:
        probe_embedding = face_service.represent(selfie_bytes)
    except ValueError as error:
        with get_db() as conn:
            cursor = conn.cursor()
            record_verification_attempt(
                cursor,
                None,
                payload.device_identifier,
                "Identify",
                "Failed",
                0.0,
                1.0,
                None,
                str(error),
                provider_reference_label(),
            )
            conn.commit()
        raise HTTPException(status_code=400, detail=str(error))

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                FT.FaceTemplateId,
                FT.PayrollId AS EmployeeId,
                FT.EmbeddingJson,
                E.FirstName,
                E.LastName
            FROM dbo.FaceTemplates FT
            INNER JOIN dbo.Employees E ON E.PayrollId = FT.PayrollId
            WHERE FT.IsActive = 1
              AND E.IsActive = 'Yes'
              AND FT.EmbeddingJson IS NOT NULL
            """
        )
        candidates = cursor.fetchall()
        if not candidates:
            record_verification_attempt(
                cursor,
                None,
                payload.device_identifier,
                "Identify",
                "Failed",
                0.0,
                1.0,
                None,
                "No active face enrollments are available for identification.",
                provider_reference_label(),
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
                liveness_score=1.0,
            )

        best_candidate = None
        best_confidence = 0.0
        best_distance = None

        for candidate in candidates:
            stored_embedding = face_service.embedding_from_json(candidate.EmbeddingJson)
            matched, confidence_score, distance_score = face_service.compare(probe_embedding, stored_embedding)
            if best_candidate is None or distance_score < best_distance:
                best_candidate = candidate
                best_confidence = confidence_score
                best_distance = distance_score

        if best_candidate is None or best_distance is None or best_distance > settings.face_distance_threshold:
            record_verification_attempt(
                cursor,
                None,
                payload.device_identifier,
                "Identify",
                "Failed",
                best_confidence,
                1.0,
                best_distance,
                "No enrolled employee met the DeepFace distance threshold.",
                provider_reference_label(),
            )
            conn.commit()
            return FaceClockResponse(
                success=False,
                message="No enrolled employee matched this face.",
                employee_id=None,
                full_name=None,
                event_type=None,
                verification_status="Failed",
                confidence_score=best_confidence,
                liveness_score=1.0,
            )

        full_name = f"{best_candidate.FirstName} {best_candidate.LastName}".strip()
        next_event_type = next_event_type_for_employee(cursor, best_candidate.EmployeeId)

        verification_attempt_row = record_verification_attempt(
            cursor,
            best_candidate.EmployeeId,
            payload.device_identifier,
            next_event_type,
            "Passed",
            best_confidence,
            1.0,
            best_distance,
            None,
            provider_reference_label(),
        )
        verification_attempt_id = int(verification_attempt_row.FaceVerificationAttemptId)

        cursor.execute(
            """
            EXEC dbo.usp_MobileClockEvent
                @EmployeeId = ?,
                @EventType = ?,
                @DeviceIdentifier = ?,
                @VerificationAttemptId = ?,
                @Latitude = ?,
                @Longitude = ?
            """,
            best_candidate.EmployeeId,
            next_event_type,
            payload.device_identifier,
            verification_attempt_id,
            payload.latitude,
            payload.longitude,
        )
        conn.commit()

    return FaceClockResponse(
        success=True,
        message=f"{next_event_type} recorded.",
        employee_id=best_candidate.EmployeeId,
        full_name=full_name,
        event_type=next_event_type,
        verification_status="Passed",
        confidence_score=best_confidence,
        liveness_score=1.0,
    )
