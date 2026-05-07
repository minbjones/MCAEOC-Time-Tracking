# Azure App Service Container Deployment

This repo is ready to deploy to Azure App Service for Containers with:

- `Dockerfile`
- `startup.sh`
- `.dockerignore`
- `azure-app-service-settings.example.txt`

## 1. Create Azure resources

Create:

- an Azure Container Registry
- an Azure App Service plan for Linux
- a Web App for Containers

## 2. Build and push the image

From the repo root:

```powershell
az acr build --registry <acr-name> --image mcaeoc-time-tracking:latest .
```

## 3. Point App Service at the image

Use your ACR image:

```text
<acr-name>.azurecr.io/mcaeoc-time-tracking:latest
```

## 4. Configure app settings

In Azure App Service, add the settings from `azure-app-service-settings.example.txt`.

Important:

- Do not deploy `employee_time_tracking_connection_string.txt`
- Store the real DB connection string in App Service application settings
- App Service injects `PORT`; `startup.sh` already honors it

## 5. Container startup

The container starts with:

```text
/app/startup.sh
```

That script runs:

```text
gunicorn --bind 0.0.0.0:${PORT} app:app
```

## 6. Recommended Azure settings

- OS: Linux
- Port: `8000`
- Health check path: `/`

## 7. After deployment

Verify:

- the site loads
- database connectivity works
- login works
- SMTP settings are correct if forgot-password is enabled
