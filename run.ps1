$ErrorActionPreference = "Stop"

Set-Location -Path $PSScriptRoot
$connectionStringFile = Join-Path $PSScriptRoot "employee_time_tracking_connection_string.txt"
$defaultConnectionString = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=BLANTON-I9\SQLEXPRESS;DATABASE=EmployeeTimeTracking;Trusted_Connection=yes;"

if (Test-Path $connectionStringFile) {
    $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING = (Get-Content $connectionStringFile -Raw).Trim()
    Write-Host "Using connection string from employee_time_tracking_connection_string.txt"
} else {
    $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING = $defaultConnectionString
    Write-Host "Using default local SQL connection string."
}

if ($env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURSERVER.database.windows.net*" -or $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURUSER*" -or $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING -like "*YOURPASSWORD*") {
    throw "Update employee_time_tracking_connection_string.txt or EMPLOYEE_TIME_TRACKING_CONNECTION_STRING with your real SQL Server connection string."
}

Write-Host "Active connection string:" $env:EMPLOYEE_TIME_TRACKING_CONNECTION_STRING

if (Test-Path ".\.venv\Scripts\python.exe") {
    Write-Host "Starting Employee Time Tracking with .venv Python..."
    Start-Process -FilePath ".\.venv\Scripts\python.exe" -ArgumentList "app.py" -WorkingDirectory $PSScriptRoot
} else {
    Write-Host "Virtual environment not found. Falling back to system Python..."
    Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $PSScriptRoot
}

Start-Sleep -Seconds 3
Start-Process "http://127.0.0.1:5000"
