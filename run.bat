@echo off
setlocal

cd /d "%~dp0"
set "PYTHON_EXE=C:\Users\minbj\AppData\Local\Programs\Python\Python312\python.exe"
set "CONNECTION_STRING_FILE=%~dp0employee_time_tracking_connection_string.txt"
set "DEFAULT_CONNECTION_STRING=DRIVER={ODBC Driver 17 for SQL Server};SERVER=BLANTON-I9\SQLEXPRESS;DATABASE=EmployeeTimeTracking;Trusted_Connection=yes;"

if exist "%CONNECTION_STRING_FILE%" (
    set /p EMPLOYEE_TIME_TRACKING_CONNECTION_STRING=<"%CONNECTION_STRING_FILE%"
    echo Using connection string from employee_time_tracking_connection_string.txt
) else (
    set "EMPLOYEE_TIME_TRACKING_CONNECTION_STRING=%DEFAULT_CONNECTION_STRING%"
    echo Using default local SQL connection string.
)

echo Active connection string: %EMPLOYEE_TIME_TRACKING_CONNECTION_STRING%

if exist "%PYTHON_EXE%" (
    echo Starting Employee Time Tracking with Python 3.12...
    start "Employee Time Tracking" "%PYTHON_EXE%" app.py
) else (
    echo Virtual environment not found. Falling back to system Python...
    start "Employee Time Tracking" python app.py
)

timeout /t 3 /nobreak >nul
start "" "http://127.0.0.1:5000"

endlocal
