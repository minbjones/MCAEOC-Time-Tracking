# Android Scaffold

This is a Jetpack Compose scaffold for Android face-based clock in and clock out.

## Current flow

- load the active employee list from the mobile API
- open directly to a live front-camera preview
- press `Capture` to identify the employee by face and automatically clock them in or out
- show a 3-second greeting with the employee name and the recorded event
- use `Enrollment` to open the admin-gated enrollment dialog
- unlock enrollment with admin code `1400`
- choose an employee from the SQL-backed dropdown showing full name and employee ID, then capture their face for enrollment

## Notes

- The current sample uses a real CameraX front-camera capture flow.
- `BuildConfig.BASE_URL` must match the reachable FastAPI address for your emulator or device.
- `BuildConfig.MOBILE_API_KEY` must match the backend API key.
- The backend currently uses DeepFace-based enrollment and matching through the mobile API.
- The app uses a blue gradient background with dark blue buttons and white lettering.

## Next Android steps

1. Add capture guidance overlays and better retry UX.
2. Add secure token storage with encrypted preferences.
3. Add optional GPS capture and permission handling.
4. Add a production liveness check flow.
