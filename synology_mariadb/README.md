# Synology MariaDB Test Variant

This folder is a separate MariaDB/Synology test copy of the Flask app so your main SQL Server app stays untouched.

## What is included

- a copied Flask web app adapted toward MariaDB
- Docker files for Synology Container Manager
- a MariaDB schema/bootstrap script
- a FastAPI mobile API for Android

## What this variant is for

- testing the web app on a Synology NAS with Container Manager
- testing MariaDB as a replacement for SQL Server

## Current status

- the Flask web app is migrated into this MariaDB test branch
- the Android-facing FastAPI mobile backend is also present in `mobile_api`
- Azure SQL deployment pieces are intentionally not part of this Synology/MariaDB path

## Start locally or on Synology

Use `compose.yaml` in this folder.

1. Update the passwords in `compose.yaml`.
2. In Synology Container Manager, create a project from this folder.
3. Start the project.
4. Open `http://<nas-ip>:8000` for the web app.
5. The Android/mobile API is available at `http://<nas-ip>:8001`.

If Synology only allows compose-file upload and not a full project folder, use:

- [docker-compose.upload.yml](</C:/Users/minbj/Documents/MCAEOC Time Tracking/synology_mariadb/docker-compose.upload.yml>)
- [IMAGE_DEPLOYMENT.md](</C:/Users/minbj/Documents/MCAEOC Time Tracking/synology_mariadb/IMAGE_DEPLOYMENT.md>)

That upload-only flow requires prebuilt images for `web` and `mobile_api`.
The exact GHCR workflow is in [synology-ghcr-images.yml](</C:/Users/minbj/Documents/MCAEOC Time Tracking/.github/workflows/synology-ghcr-images.yml>).

## Android app

The main Android project still defaults to the Azure mobile API in the primary app branch.

To test Android against this Synology/MariaDB stack, override it at build time with a Gradle property:

```powershell
./gradlew.bat assembleDebug -PmobileApiBaseUrl=http://<nas-ip>:8001/ -PmobileApiKey=your-api-key
```

## Default seeded owner account

- email: `admin@mcaeoc.org`
- user ID: `admin`
- password: `Bl@nton!2008`

The account is seeded with `MustChangePassword = 0` in this test variant.

## Important note

This is a migration workspace, not a guaranteed feature-complete production replacement yet. It is meant to let you test the core Flask web app on Synology/MariaDB without risking your current SQL Server deployment.
