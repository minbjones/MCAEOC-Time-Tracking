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
set "EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY=i-was-in-the-stable-when-jesus-was-born"

if not exist "%PYTHON_EXE%" (
    echo Python 3.12 was not found at %PYTHON_EXE%
    pause
    exit /b 1
)

echo Installing or verifying root application dependencies...
"%PYTHON_EXE%" -m pip install -r requirements.txt

echo Installing or verifying mobile API dependencies...
"%PYTHON_EXE%" -m pip install -r mobile_api\requirements.txt

echo Starting Flask GUI...
start "Employee Time Tracking GUI" "%PYTHON_EXE%" app.py

echo Starting FastAPI mobile backend...
start "Employee Time Tracking Mobile API" /D "%~dp0mobile_api" cmd /c ""%PYTHON_EXE%" -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"

timeout /t 5 /nobreak >nul
start "" "http://127.0.0.1:5000"
start "" "http://127.0.0.1:8000/health"

endlocal
