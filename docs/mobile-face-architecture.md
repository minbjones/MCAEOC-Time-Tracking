# Mobile Face Clocking Architecture

## Recommended flow

1. Employee signs in on Android with username and password.
2. Android registers the device with the backend.
3. Employee enrolls a face template on the device.
4. The backend stores an encrypted face template reference and audit trail.
5. For clock in or clock out:
   - the Android app captures a live selfie
   - a liveness check runs
   - the app verifies the live face against that employee's enrolled template
   - the backend records the verification attempt
   - the backend writes the clock event to `dbo.TimeEntries`

## Key SQL additions

- `dbo.MobileDevices`: trusted Android devices per employee
- `dbo.FaceTemplates`: encrypted biometric template records
- `dbo.FaceVerificationAttempts`: audit log for every facial verification
- new `dbo.TimeEntries` columns for `ClockMethod`, device, location, and verification linkage

## Security notes

- Do not let Android connect directly to SQL Server.
- Put all mobile access behind an authenticated API.
- Store encrypted face templates or provider references, not raw selfie images by default.
- Require liveness scoring before clock events are accepted.
- Consider fallback approval flows for false negatives.

## Concrete provider in this scaffold

The current scaffold uses Azure Face REST:

- person group creation for an employee collection
- person creation per employee
- persisted face enrollment
- live selfie `detect`
- face-to-person `verify`

Inference: the scaffold currently treats Azure verification as the concrete identity check and leaves production-grade liveness as a separate hardening step.

## Minimal mobile endpoints

- `POST /api/mobile/auth/login`
- `POST /api/mobile/devices/register`
- `POST /api/mobile/face/enroll`
- `POST /api/mobile/clock/verify-and-clock`
- `GET /api/mobile/me`
