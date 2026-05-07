$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$venvPython = Join-Path $projectRoot ".venv\Scripts\python.exe"
$venvPip = Join-Path $projectRoot ".venv\Scripts\pip.exe"
$mobileApiDir = Join-Path $projectRoot "mobile_api"
$azureSqlConnectionString = "Driver={ODBC Driver 18 for SQL Server};Server=tcp:mcaeoc-time-clock-1.database.windows.net,1433;Initial Catalog=EmployeeTimeTracking;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=`"Active Directory Default`";"

if (-not (Test-Path $venvPython)) {
    throw "Virtual environment Python was not found at $venvPython"
}

$env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING = $azureSqlConnectionString
$env:AZURE_FACE_ENDPOINT = "https://mcaeoc-timeclock.cognitiveservices.azure.com/"
$env:AZURE_FACE_KEY = "DlcR9Sde6AFCkc5k6XQUo8bT4UlazWPBhNzuUVnbj878gb7Gzq5tJQQJ99CDACYeBjFXJ3w3AAAKACOG4vsc"
$env:AZURE_FACE_PERSON_GROUP_ID = "employee-time-tracking"
$env:EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY = "i-was-in-the-stable-when-jesus-was-born"

if ($env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURSERVER.database.windows.net*" -or $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURUSER*" -or $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURPASSWORD*") {
    throw "Update the Azure SQL Database connection string in run_all.ps1 with your real server, username, and password."
}

Write-Host "Installing or verifying root application dependencies..."
& $venvPython -m pip install -r (Join-Path $projectRoot "requirements.txt")

Write-Host "Installing or verifying mobile API dependencies..."
& $venvPython -m pip install -r (Join-Path $mobileApiDir "requirements.txt")

Write-Host "Starting Flask GUI on http://127.0.0.1:5000 ..."
Start-Process -FilePath $venvPython -ArgumentList "app.py" -WorkingDirectory $projectRoot

Write-Host "Starting FastAPI mobile backend on http://127.0.0.1:8000 ..."
Start-Process -FilePath $venvPython -ArgumentList "-m uvicorn main:app --reload --host 0.0.0.0 --port 8000" -WorkingDirectory $mobileApiDir

Start-Sleep -Seconds 5

Start-Process "http://127.0.0.1:5000"
Start-Process "http://127.0.0.1:8000/health"
