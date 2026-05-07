# Employee Time Tracking

This project includes a Python Flask application with an HTML interface and a Microsoft SQL Server script for the `EmployeeTimeTracking` backend.

It now also includes:

- a SQL migration for Android face-based clock in and clock out
- a Python FastAPI mobile backend scaffold
- an Android Jetpack Compose scaffold

## Features

- Employee login with required password creation on first login
- Forgot password flow that emails a temporary password
- Clock in and clock out
- Request annual, sick, or personal leave based on employee program type
- View annual, sick, and personal leave balances
- View and print a bi-weekly timesheet
- Leave approval page for `Owner`, `Executive Director`, `Director`, and `Manager`
- Owner-only employee setup page for entering hire date, funding source, and workflow supervisor
- workflow supervisor relationships support scoped visibility
- Live In/Out Board for supervisory roles
- Review Timesheets page for Director, Executive Director, and Manager

## Seeded Users

Most seeded users begin with the temporary password `Welcome1!` and must change it after signing in.

- `priscilla.johnson`
- `decarla.rinkines`
- `juanita.medlin`
- `clark.phillips`
- `shirley.pulliam`
- `blanton.jones`
- `jacqueline.burton`

Additional seeded owner account:

- `admin`
  Password: `Bl@nton!2008`

## Database Setup

1. Open SQL Server Management Studio.
2. Run `database.sql`.
3. Confirm SQL Server is reachable from the Flask app machine.

## App Setup

1. Create a virtual environment.
2. Install dependencies with `pip install -r requirements.txt`.
3. Set the connection string if your SQL Server instance differs from localhost.
4. If you want the forgot-password email flow, set SMTP environment variables.
5. Run `python app.py`.

Example connection string:

`DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=EmployeeTimeTracking;Trusted_Connection=yes;`

SMTP settings used by the forgot-password flow:

- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_FROM_EMAIL`
- `SMTP_FROM_NAME` optional
- `SMTP_USERNAME` optional
- `SMTP_PASSWORD` optional
- `SMTP_USE_TLS` optional, defaults to `true`
- `SMTP_USE_SSL` optional, defaults to `false`

## One-Click Startup

You can start the app with either launcher from [C:\Users\minbj\Documents\New project](C:\Users\minbj\Documents\New project):

- [run.bat](C:\Users\minbj\Documents\New project\run.bat)
- [run.ps1](C:\Users\minbj\Documents\New project\run.ps1)

Both scripts:

- switch into the project folder
- set the SQL Server connection string for `BLANTON-I9\SQLEXPRESS` if it is not already set
- use `.venv\Scripts\python.exe` when available
- otherwise fall back to `python app.py`
- open the browser automatically to `http://127.0.0.1:5000`

## Mobile Face Clocking

Files added for the Android mobile path:

- [sql/mobile_face_migration.sql](C:\Users\minbj\Documents\New project\sql\mobile_face_migration.sql)
- [docs/mobile-face-architecture.md](C:\Users\minbj\Documents\New project\docs\mobile-face-architecture.md)
- [mobile_api](C:\Users\minbj\Documents\New project\mobile_api)
- [android](C:\Users\minbj\Documents\New project\android)
- [run_mobile_api.ps1](C:\Users\minbj\Documents\New project\run_mobile_api.ps1)
- [run_all.ps1](C:\Users\minbj\Documents\New project\run_all.ps1)
- [run_all.bat](C:\Users\minbj\Documents\New project\run_all.bat)

Suggested rollout:

1. Run the base database script.
2. Run the mobile migration script.
3. Start the FastAPI mobile backend from `mobile_api` or use [run_mobile_api.ps1](C:\Users\minbj\Documents\New project\run_mobile_api.ps1).
4. Open the Android project in Android Studio.

The mobile API and Android app are scaffolds. The biometric verifier is still a placeholder and should be replaced with a real face verification and liveness provider before production use.

## One-Click Full Startup

To start the Flask GUI and the FastAPI mobile backend together, use either:

- [run_all.ps1](C:\Users\minbj\Documents\New project\run_all.ps1)
- [run_all.bat](C:\Users\minbj\Documents\New project\run_all.bat)

These launchers:

- load the SQL Server and Azure Face environment settings
- install or verify both root and mobile API Python dependencies
- start the Flask GUI on `127.0.0.1:5000`
- start the FastAPI mobile backend on `127.0.0.1:8000`
- open both local pages automatically

## Owner Employee Setup

After signing in as `blanton.jones`, use the `Employees` link in the top navigation to create employees.

The Owner can enter:

- first name and last name
- email
- user ID
- funding source
- role
- hire date
- workflow supervisor user ID
- temporary password

New employees must change their password at first login.

The Owner can also import employees by CSV from the `Employees` page. Existing employees are matched by payroll ID first, then email, then user ID. If the CSV payroll ID does not already exist in the app database, the row is treated as a new employee and the database assigns the next payroll ID for the selected funding source using a 6-digit padded sequence. Required columns are:

- `first_name`
- `last_name`
- `email`
- `hire_date`
- `temporary_password`
- `personal_leave`
- `funding_id` or `funding_source`

Optional CSV columns are:

- `payroll_id`
- `user_id`
- `role_name`
- `workflow`
- `is_active`

If `temporary_password` is blank for a non-owner employee, the app generates a secure temporary password automatically and shows it once after the import. Owner rows must still provide an explicit temporary password.

After each CSV import, the Owner can download a mapping file that shows the original CSV payroll ID beside the actual database payroll ID assigned or updated by the app.

Funding sources available in the current schema are:

- `20 Head Start-2`
- `21 ADMIN`
- `22 Head Start`
- `24 ABC`
- `44 CSBG`
- `50 HIPPY`
- `51 HEAP/LIHEAP`
- `99 FINANCE`

The Owner can also edit existing employees, including:

- role
- workflow supervisor
- hire date
- email
- user ID
- active or inactive status

To edit, click an employee from the list on the `Employees` page, then update the single edit form for that employee.

Executive Director, Director, and Manager users can approve or deny leave for their subordinates. Subordinates can request leave and cancel only their own pending requests. Executive Director, Director, and Manager can review subordinate timesheets, and Executive Director plus Manager can modify subordinate clock entries. Managers do not have access to the `Employees` page.

## Session and Confirmation Prompts

- users are forced to log out after 10 minutes of inactivity
- editable forms prompt before saving
- the Owner gets an extra confirmation when changing an employee hire date
- clock-in and clock-out times are displayed in 12-hour format with AM/PM
- clock-out displays the date too when it occurs on a different day than clock-in
- all displayed dates use `MM/DD/YYYY`
- the employee timesheet header includes the requested agency name, employee name/ID, and leave balances
- print and PDF export are available from the timesheet view page, with print using the browser print dialog
- employees marked `IsHeadStart = 1` accrue `Personal` and `Sick`; all others accrue `Annual` and `Sick`
- bi-weekly leave accruals post automatically at the end of each pay period on the payroll calendar that begins with the 04/24/2026 period-end date, with each period posting only once
- reporting hierarchy features for `ReportsTo`, new roles, the live board, and scoped approvals can be applied with [repair_reporting_roles_and_board.sql](C:\Users\minbj\Documents\New project\sql\repair_reporting_roles_and_board.sql)
