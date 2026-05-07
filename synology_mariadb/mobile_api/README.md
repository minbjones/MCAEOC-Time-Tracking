# Synology MariaDB Mobile API

This is the Android-facing mobile API for the Synology/MariaDB test stack.

## Features

- `GET /health`
- `GET /api/mobile/employees`
- `POST /api/mobile/auth/login`
- `POST /api/mobile/devices/register`
- `POST /api/mobile/face/enroll`
- `POST /api/mobile/clock/verify-and-clock`
- `POST /api/mobile/clock/identify-and-clock`

## Face recognition

This variant uses the open-source Python library `deepface` for:

- face enrollment
- 1:1 verification
- 1:N identification

Embeddings are stored in MariaDB in `dbo.FaceTemplates`.

## Recommended small-business defaults

This Synology variant is tuned by default for a small-business time clock workflow:

- model: `ArcFace`
- detector: `ssd`
- distance threshold: `0.30`
- alignment: enabled
- detection required: enabled
- face crop expansion: `10%`
- uploaded image max side: `1280`

These defaults bias toward fewer false accepts while staying lighter than RetinaFace on a NAS.

You can override them with:

- `FACE_MODEL_NAME`
- `FACE_DETECTOR_BACKEND`
- `FACE_DISTANCE_THRESHOLD`
- `FACE_ALIGN`
- `FACE_ENFORCE_DETECTION`
- `FACE_EXPAND_PERCENTAGE`
- `FACE_MAX_IMAGE_SIZE`

## Notes

- This is intended for Synology testing, not a finished production biometric system.
- Liveness detection is not implemented.
- You should still tune `FACE_DISTANCE_THRESHOLD` for your environment before relying on payroll decisions.
