# Mobile API

This FastAPI service is a scaffold backend for Android face-based clock in and clock out.

## Endpoints

- `POST /api/mobile/auth/login`
- `POST /api/mobile/devices/register`
- `POST /api/mobile/face/enroll`
- `POST /api/mobile/clock/verify-and-clock`
- `POST /api/mobile/clock/identify-and-clock`

## Run

```powershell
cd mobile_api
..\.venv\Scripts\pip.exe install -r requirements.txt
..\.venv\Scripts\uvicorn.exe main:app --reload --host 0.0.0.0 --port 8000
```

On first successful database connection, the API now auto-applies the mobile face schema from `sql/mobile_face_migration.sql`, including `dbo.FaceTemplates`.

Set:

- `EMPLOYEE_TIME_TRACKING_CONNECTION_STRING`
- `EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY`
- `FACE_MODEL_NAME`
- `FACE_DETECTOR_BACKEND`
- `FACE_DISTANCE_THRESHOLD`
- `FACE_ALIGN`
- `FACE_ENFORCE_DETECTION`
- `FACE_EXPAND_PERCENTAGE`
- `FACE_MAX_IMAGE_SIZE`

## Important

This scaffold now uses DeepFace for face enrollment, verification, and identification while keeping the current Azure-hosted MSSQL app and Android API contract intact.

Mobile auth now uses employee email for sign-in. The mobile employee list and face APIs still return `employee_id` and `full_name`, but `employee_id` now represents the employee `PayrollId` from the database schema.

Liveness is not implemented as a production-grade provider flow in this scaffold. Add a supported liveness SDK or provider check before production use.
