$ErrorActionPreference = "Stop"

Set-Location -Path (Join-Path $PSScriptRoot "mobile_api")
$venvUvicorn = Join-Path $PSScriptRoot ".venv\Scripts\uvicorn.exe"
$venvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
$azureSqlConnectionString = "Driver={ODBC Driver 18 for SQL Server};Server=tcp:mcaeoc-time-clock-1.database.windows.net,1433;Initial Catalog=EmployeeTimeTracking;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=`"Active Directory Default`";"

$env:AZURE_FACE_ENDPOINT = "https://mcaeoc-timeclock.cognitiveservices.azure.com/"
$env:AZURE_FACE_KEY = "DlcR9Sde6AFCkc5k6XQUo8bT4UlazWPBhNzuUVnbj878gb7Gzq5tJQQJ99CDACYeBjFXJ3w3AAAKACOG4vsc"
$env:AZURE_FACE_PERSON_GROUP_ID = "employee-time-tracking"
$env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING = $azureSqlConnectionString
$env:EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY = "i-was-in-the-stable-when-jesus-was-born"

if ([string]::IsNullOrWhiteSpace($env:AZURE_FACE_ENDPOINT) -or $env:AZURE_FACE_ENDPOINT -like "https://your-face-resource*") {
    throw "AZURE_FACE_ENDPOINT is not set to a real Azure Face endpoint."
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_FACE_KEY) -or $env:AZURE_FACE_KEY -eq "your-azure-face-key") {
    throw "AZURE_FACE_KEY is not set to a real Azure Face key."
}

if ([string]::IsNullOrWhiteSpace($env:EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY) -or $env:EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY -eq "change-me") {
    throw "EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY must be set to a real shared secret."
}

if ($env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURSERVER.database.windows.net*" -or $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURUSER*" -or $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURPASSWORD*") {
    throw "Update the Azure SQL Database connection string in run_mobile_api.ps1 with your real server, username, and password."
}

Write-Host "Starting Employee Time Tracking Mobile API..."
Write-Host "AZURE_FACE_ENDPOINT: $env:AZURE_FACE_ENDPOINT"
Write-Host "AZURE_FACE_PERSON_GROUP_ID: $env:AZURE_FACE_PERSON_GROUP_ID"

if (-not (Test-Path $venvPython)) {
    throw "Virtual environment Python was not found at $venvPython"
}

if (-not (Test-Path $venvUvicorn)) {
    Write-Host "Uvicorn is not installed in .venv. Installing mobile API dependencies..."
    & $venvPython -m pip install -r "requirements.txt"
}

if (Test-Path $venvUvicorn) {
    Start-Process -FilePath $venvUvicorn -ArgumentList "main:app --reload --host 0.0.0.0 --port 8000" -WorkingDirectory (Get-Location)
} elseif (Test-Path $venvPython) {
    Start-Process -FilePath $venvPython -ArgumentList "-m uvicorn main:app --reload --host 0.0.0.0 --port 8000" -WorkingDirectory (Get-Location)
} else {
    Start-Process -FilePath "uvicorn" -ArgumentList "main:app --reload --host 0.0.0.0 --port 8000" -WorkingDirectory (Get-Location)
}

Start-Sleep -Seconds 3
Start-Process "http://127.0.0.1:8000/health"
