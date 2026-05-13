from __future__ import annotations

import json

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse

from config import settings
from database import get_db
from parser import normalize_punch_timestamp, parse_payload


app = FastAPI(title=settings.api_title)


def truncate_raw_payload(body_text: str) -> str | None:
    if not settings.save_raw_payloads:
        return None
    if len(body_text) <= settings.raw_payload_max_length:
        return body_text
    return body_text[: settings.raw_payload_max_length]


def create_request_log(cursor, *, request_path: str, http_method: str, device_identifier: str | None, remote_address: str | None, query_string: str, headers_json: str, body_text: str, parsed_record_count: int):
    cursor.execute(
        """
        INSERT INTO dbo.AdmsRequestLogs
        (
            RequestPath,
            HttpMethod,
            DeviceIdentifier,
            RemoteAddress,
            QueryString,
            HeadersJson,
            BodyText,
            ParsedRecordCount,
            ImportStatus
        )
        VALUES
        (
            ?, ?, ?, ?, ?, ?, ?, ?, 'Pending'
        )
        """,
        request_path,
        http_method,
        device_identifier,
        remote_address,
        query_string,
        headers_json,
        truncate_raw_payload(body_text),
        parsed_record_count,
    )
    return cursor.lastrowid


def finalize_request_log(cursor, request_log_id: int, *, imported_record_count: int, status: str, failure_reason: str | None):
    cursor.execute(
        """
        UPDATE dbo.AdmsRequestLogs
        SET ImportedRecordCount = ?,
            ImportStatus = ?,
            FailureReason = ?,
            UpdatedAt = UTC_TIMESTAMP(6)
        WHERE AdmsRequestLogId = ?
        """,
        imported_record_count,
        status,
        failure_reason,
        request_log_id,
    )


@app.get("/")
def root_health():
    return {
        "status": "ok",
        "service": "zkteco-adms",
        "systemName": settings.system_name,
    }


@app.get("/health")
def health():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_name = 'EmployeeDeviceMappings'
                ) THEN 1 ELSE 0 END AS HasEmployeeDeviceMappings,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_name = 'DevicePunchImports'
                ) THEN 1 ELSE 0 END AS HasDevicePunchImports,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM information_schema.routines
                    WHERE routine_schema = DATABASE()
                      AND routine_type = 'PROCEDURE'
                      AND routine_name = 'usp_ImportDevicePunch'
                ) THEN 1 ELSE 0 END AS HasImportProcedure
            """
        )
        row = cursor.fetchone()
    return {
        "status": "ok",
        "service": "zkteco-adms",
        "systemName": settings.system_name,
        "databaseConnected": True,
        "employeeDeviceMappingsTablePresent": bool(row.HasEmployeeDeviceMappings),
        "devicePunchImportsTablePresent": bool(row.HasDevicePunchImports),
        "importProcedurePresent": bool(row.HasImportProcedure),
    }


@app.get("/iclock/getrequest")
def get_request():
    return PlainTextResponse("OK")


@app.post("/iclock/devicecmd")
async def device_command():
    return PlainTextResponse("OK")


@app.api_route("/iclock/cdata", methods=["GET", "POST"])
async def receive_cdata(request: Request):
    body_bytes = await request.body()
    body_text = body_bytes.decode("utf-8", errors="replace")
    query_params = dict(request.query_params)
    device_identifier, records = parse_payload(query_params, body_text)
    device_identifier = device_identifier or settings.device_identifier_fallback
    remote_address = request.client.host if request.client else None
    headers_json = json.dumps(dict(request.headers), ensure_ascii=True)

    with get_db() as conn:
        cursor = conn.cursor()
        request_log_id = create_request_log(
            cursor,
            request_path=str(request.url.path),
            http_method=request.method,
            device_identifier=device_identifier,
            remote_address=remote_address,
            query_string=str(request.url.query),
            headers_json=headers_json,
            body_text=body_text,
            parsed_record_count=len(records),
        )

        if not records:
            finalize_request_log(
                cursor,
                request_log_id,
                imported_record_count=0,
                status="Ignored",
                failure_reason="No recognizable punch records were found in the request.",
            )
            conn.commit()
            return PlainTextResponse("OK")

        imported_count = 0
        failures: list[str] = []

        for index, record in enumerate(records, start=1):
            try:
                punch_timestamp = normalize_punch_timestamp(record["punch_timestamp"])
                raw_payload_json = json.dumps(
                    {
                        "query": query_params,
                        "record": record,
                        "body": body_text if settings.save_raw_payloads else None,
                    },
                    ensure_ascii=True,
                )
                cursor.execute(
                    """
                    EXEC dbo.usp_ImportDevicePunch ?, ?, ?, ?, ?, ?, ?
                    """,
                    settings.system_name,
                    record.get("device_identifier") or device_identifier,
                    record["external_user_id"],
                    record.get("external_user_name"),
                    punch_timestamp.strftime("%Y-%m-%d %H:%M:%S"),
                    record.get("punch_direction"),
                    raw_payload_json,
                )
                cursor.fetchone()
                imported_count += 1
            except Exception as exc:
                failures.append(f"Record {index}: {str(exc)}")

        status = "Imported" if not failures else ("Partial" if imported_count else "Failed")
        finalize_request_log(
            cursor,
            request_log_id,
            imported_record_count=imported_count,
            status=status,
            failure_reason=" | ".join(failures)[:500] if failures else None,
        )
        conn.commit()

    return PlainTextResponse("OK")


@app.get("/debug/recent")
def recent_requests(limit: int = 20):
    safe_limit = min(max(limit, 1), 200)
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                AdmsRequestLogId,
                RequestPath,
                HttpMethod,
                DeviceIdentifier,
                RemoteAddress,
                ParsedRecordCount,
                ImportedRecordCount,
                ImportStatus,
                FailureReason,
                CreatedAt,
                UpdatedAt
            FROM dbo.AdmsRequestLogs
            ORDER BY AdmsRequestLogId DESC
            LIMIT ?
            """,
            safe_limit,
        )
        rows = cursor.fetchall()
    return JSONResponse(
        [
            {
                "requestLogId": row.AdmsRequestLogId,
                "requestPath": row.RequestPath,
                "httpMethod": row.HttpMethod,
                "deviceIdentifier": row.DeviceIdentifier,
                "remoteAddress": row.RemoteAddress,
                "parsedRecordCount": row.ParsedRecordCount,
                "importedRecordCount": row.ImportedRecordCount,
                "importStatus": row.ImportStatus,
                "failureReason": row.FailureReason,
                "createdAt": row.CreatedAt.isoformat() if row.CreatedAt else None,
                "updatedAt": row.UpdatedAt.isoformat() if row.UpdatedAt else None,
            }
            for row in rows
        ]
    )
