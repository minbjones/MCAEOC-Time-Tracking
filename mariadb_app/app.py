import csv
import hashlib
import os
import re
import secrets
import smtplib
import ssl
from datetime import date, datetime, timedelta
from email.message import EmailMessage
from functools import wraps
from io import BytesIO, StringIO
from typing import Optional

import pyodbc
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from flask import (
    Flask,
    flash,
    redirect,
    render_template,
    request,
    send_file,
    session,
    url_for,
)


app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "change-this-secret-key")
app.permanent_session_lifetime = timedelta(minutes=10)
CONNECTION_STRING_FILE = os.path.join(os.path.dirname(__file__), "employee_time_tracking_connection_string.txt")
_connection_target_logged = False
_password_setup_schema_ready = False
PAY_PERIOD_END_ANCHOR = date(2026, 4, 24)

LEAVE_APPROVER_ROLES = {"Owner", "Executive Director", "Director", "Manager"}
MANUAL_LEAVE_ENTRY_ROLES = {"Owner", "Leave Manager"}
TIMESHEET_REVIEW_ROLES = {"Owner", "Executive Director", "Director", "Manager"}
TIME_EDIT_ROLES = {"Owner", "Executive Director", "Director", "Manager"}
SUPERVISOR_ROLES = {"Owner", "Executive Director", "Director", "Manager"}
CLOCK_MANAGEMENT_ROLES = {"Owner", "Executive Director", "Director"}
CLOCK_SELF_ROLES = {"Owner", "Executive Director", "Director"}


def format_datetime_12h(value):
    if not value:
        return ""
    return value.strftime("%m/%d/%Y %I:%M %p")


def format_date_mmddyyyy(value):
    if not value:
        return ""
    return value.strftime("%m/%d/%Y")


def format_time_12h(value):
    if not value:
        return ""
    return value.strftime("%I:%M %p")


def format_clock_boundary(clock_in_value, clock_out_value):
    if not clock_out_value:
        return "Open"
    if clock_in_value and clock_in_value.date() != clock_out_value.date():
        return format_datetime_12h(clock_out_value)
    return format_time_12h(clock_out_value)


app.jinja_env.filters["datefmt"] = format_date_mmddyyyy
app.jinja_env.filters["datetime12"] = format_datetime_12h
app.jinja_env.filters["time12"] = format_time_12h
app.jinja_env.globals["format_clock_boundary"] = format_clock_boundary


def get_connection():
    global _connection_target_logged
    if os.path.exists(CONNECTION_STRING_FILE):
        with open(CONNECTION_STRING_FILE, "r", encoding="utf-8") as connection_string_file:
            conn_str = connection_string_file.read().strip()
    else:
        conn_str = os.getenv(
            "EMPLOYEE_TIME_TRACKING_CONNECTION_STRING",
            "DRIVER={ODBC Driver 17 for SQL Server};"
            "SERVER=localhost;"
            "DATABASE=EmployeeTimeTracking;"
            "Trusted_Connection=yes;",
        )
    conn = pyodbc.connect(conn_str)
    if not _connection_target_logged:
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT @@SERVERNAME AS ServerName, DB_NAME() AS DatabaseName")
            row = cursor.fetchone()
            print(
                f"[Employee Time Tracking] Connected to server={row.ServerName} database={row.DatabaseName}",
                flush=True,
            )
        except pyodbc.Error:
            pass
        _connection_target_logged = True
    return conn


def ensure_role_catalog(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT RoleId FROM dbo.Roles WHERE RoleName = ?", "Leave Manager")
    if not cursor.fetchone():
        cursor.execute("INSERT INTO dbo.Roles (RoleName) VALUES (?)", "Leave Manager")
        conn.commit()


def hash_password(salt: str, password: str) -> str:
    # Match SQL Server HASHBYTES over NVARCHAR input, which uses UTF-16LE encoding.
    return hashlib.sha256(f"{salt}{password}".encode("utf-16le")).hexdigest().upper()


def login_required(view_func):
    @wraps(view_func)
    def wrapped_view(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login"))
        last_check = session.get("last_biweekly_accrual_check")
        today_stamp = date.today().isoformat()
        if last_check != today_stamp:
            with get_connection() as conn:
                ensure_role_catalog(conn)
                ensure_biweekly_leave_accruals(conn)
            session["last_biweekly_accrual_check"] = today_stamp
        return view_func(*args, **kwargs)

    return wrapped_view


def roles_required(*allowed_roles):
    def decorator(view_func):
        @wraps(view_func)
        def wrapped_view(*args, **kwargs):
            if session.get("role_name") not in allowed_roles:
                flash("You do not have permission to access that page.", "error")
                return redirect(url_for("dashboard"))
            return view_func(*args, **kwargs)

        return wrapped_view

    return decorator


def current_employee_id() -> int:
    return int(session["user"]["employee_id"])


def current_user_id() -> str:
    return str(session["user"]["user_id"])


def current_role_name() -> str:
    return str(session.get("role_name", ""))


def role_can(role_name: str, allowed_roles) -> bool:
    return role_name in allowed_roles


def normalize_user_id_candidate(value: str) -> str:
    cleaned = []
    previous_was_separator = False
    for char in value.strip().lower():
        if char.isalnum():
            cleaned.append(char)
            previous_was_separator = False
        elif char in {".", "_", "-"}:
            if cleaned and not previous_was_separator:
                cleaned.append(".")
                previous_was_separator = True
    return "".join(cleaned).strip(".")


def build_default_user_id(first_name: str, last_name: str, email: str = "") -> str:
    first = normalize_user_id_candidate(first_name)
    last = normalize_user_id_candidate(last_name)
    if first and last:
        return f"{first}.{last}"
    email = (email or "").strip().lower()
    if email:
        email_name = email.split("@", 1)[0]
        normalized_email_name = normalize_user_id_candidate(email_name)
        if normalized_email_name:
            return normalized_email_name
    return first or last


def normalize_user_id_input(raw_user_id: str, first_name: str, last_name: str, email: str = "") -> str:
    normalized = normalize_user_id_candidate(raw_user_id or "")
    if normalized:
        return normalized
    return build_default_user_id(first_name, last_name, email)


def validate_password_complexity(password: str) -> Optional[str]:
    if len(password) < 8:
        return "Password must be at least 8 characters."
    if not re.search(r"[A-Z]", password):
        return "Password must include at least one uppercase letter."
    if not re.search(r"[a-z]", password):
        return "Password must include at least one lowercase letter."
    if not re.search(r"[0-9]", password):
        return "Password must include at least one number."
    if not re.search(r"[^A-Za-z0-9]", password):
        return "Password must include at least one special character."
    return None


def env_flag(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def smtp_settings() -> dict:
    return {
        "host": os.getenv("SMTP_HOST", "").strip(),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "username": os.getenv("SMTP_USERNAME", "").strip(),
        "password": os.getenv("SMTP_PASSWORD", ""),
        "from_email": os.getenv("SMTP_FROM_EMAIL", "").strip(),
        "from_name": os.getenv("SMTP_FROM_NAME", "MCAEOC Employee Time Tracking").strip(),
        "use_tls": env_flag("SMTP_USE_TLS", True),
        "use_ssl": env_flag("SMTP_USE_SSL", False),
    }


def password_reset_email_is_configured() -> bool:
    settings = smtp_settings()
    return bool(settings["host"] and settings["from_email"])


def invitations_enabled() -> bool:
    return env_flag("ENABLE_PASSWORD_SETUP_EMAIL", False)


def send_password_setup_email(recipient_email: str, recipient_name: str, setup_link: str):
    settings = smtp_settings()
    if not password_reset_email_is_configured():
        raise RuntimeError(
            "Password setup email is not configured. Set SMTP_HOST and SMTP_FROM_EMAIL first."
        )

    message = EmailMessage()
    message["Subject"] = "Set up your MCAEOC Employee Time Tracking password"
    message["From"] = (
        f"{settings['from_name']} <{settings['from_email']}>"
        if settings["from_name"]
        else settings["from_email"]
    )
    message["To"] = recipient_email
    safe_name = recipient_name or "Employee"
    message.set_content(
        "\n".join(
            [
                f"Hello {safe_name},",
                "",
                "A password setup or reset was requested for your MCAEOC Employee Time Tracking account.",
                "",
                "Use the secure one-time link below to create your password:",
                setup_link,
                "",
                "This link can only be used once and will expire automatically.",
                "If you did not expect this message, contact your administrator right away.",
            ]
        )
    )

    username = settings["username"] or None
    password = settings["password"] or None

    if settings["use_ssl"]:
        with smtplib.SMTP_SSL(
            settings["host"],
            settings["port"],
            context=ssl.create_default_context(),
        ) as server:
            if username:
                server.login(username, password or "")
            server.send_message(message)
        return

    with smtplib.SMTP(settings["host"], settings["port"]) as server:
        if settings["use_tls"]:
            server.starttls(context=ssl.create_default_context())
        if username:
            server.login(username, password or "")
        server.send_message(message)


def ensure_password_setup_schema(conn):
    global _password_setup_schema_ready
    if _password_setup_schema_ready:
        return

    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS dbo.PasswordSetupTokens
        (
            PasswordSetupTokenId INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            EmployeeId INT NOT NULL,
            TokenHash CHAR(64) NOT NULL,
            Purpose VARCHAR(30) NOT NULL DEFAULT 'Setup',
            ExpiresAt DATETIME(6) NOT NULL,
            UsedAt DATETIME(6) NULL,
            CreatedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            CONSTRAINT FK_PasswordSetupTokens_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
            UNIQUE KEY UX_PasswordSetupTokens_TokenHash (TokenHash)
        ) ENGINE=InnoDB
        """
    )
    conn.commit()
    _password_setup_schema_ready = True


def hash_setup_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest().upper()


def build_app_base_url() -> str:
    configured = os.getenv("APP_BASE_URL", "").strip()
    if configured:
        return configured.rstrip("/")

    try:
        return request.url_root.rstrip("/")
    except RuntimeError:
        return "http://localhost:8000"


def create_password_setup_link(conn, employee_id: int, purpose: str = "Setup", expires_hours: int = 24) -> str:
    ensure_password_setup_schema(conn)
    cursor = conn.cursor()
    cursor.execute(
        """
        UPDATE dbo.PasswordSetupTokens
        SET UsedAt = UTC_TIMESTAMP(6)
        WHERE EmployeeId = ?
          AND UsedAt IS NULL
        """,
        employee_id,
    )

    token = secrets.token_urlsafe(32)
    token_hash = hash_setup_token(token)
    cursor.execute(
        """
        INSERT INTO dbo.PasswordSetupTokens
        (
            EmployeeId,
            TokenHash,
            Purpose,
            ExpiresAt
        )
        VALUES
        (
            ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(6), INTERVAL ? HOUR)
        )
        """,
        employee_id,
        token_hash,
        purpose,
        expires_hours,
    )
    conn.commit()
    return f"{build_app_base_url()}/set-password/{token}"


def is_seeded_owner_account(user) -> bool:
    if not user:
        return False
    return (
        str(getattr(user, "Email", "")).strip().lower() == "admin@mcaeoc.org"
        and str(getattr(user, "RoleName", "")).strip() == "Owner"
    )


def parse_csv_bool(value: str) -> int:
    normalized = (value or "").strip().lower()
    if normalized in {"1", "true", "t", "yes", "y", "personal", "personal leave"}:
        return 1
    if normalized in {"0", "false", "f", "no", "n", "annual", "annual leave"}:
        return 0
    raise ValueError("Use Personal/Annual, Yes/No, True/False, or 1/0 for Leave Type.")


def parse_csv_yes_no(value: str, field_label: str) -> str:
    normalized = (value or "").strip().lower()
    if normalized in {"1", "true", "t", "yes", "y"}:
        return "Yes"
    if normalized in {"0", "false", "f", "no", "n"}:
        return "No"
    raise ValueError(f"Use Yes/No, True/False, or 1/0 for {field_label}.")


def normalize_csv_column_name(fieldname: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "_", (fieldname or "").strip().lower()).strip("_")
    aliases = {
        "firstname": "first_name",
        "first_name": "first_name",
        "lastname": "last_name",
        "last_name": "last_name",
        "email": "email",
        "email_address": "email",
        "userid": "user_id",
        "user_id": "user_id",
        "payrollid": "payroll_id",
        "payroll_id": "payroll_id",
        "departmentid": "department_id",
        "department_id": "department_id",
        "fundingid": "department_id",
        "funding_id": "department_id",
        "department": "department_name",
        "departmentname": "department_name",
        "department_name": "department_name",
        "fundingsource": "department_name",
        "funding_source": "department_name",
        "rolename": "role_name",
        "role_name": "role_name",
        "personalleave": "personal_leave",
        "personal_leave": "personal_leave",
        "leavetype": "personal_leave",
        "leave_type": "personal_leave",
        "isheadstart": "personal_leave",
        "is_head_start": "personal_leave",
        "reportstouserid": "reports_to_user_id",
        "reports_to_user_id": "reports_to_user_id",
        "workflow": "reports_to_user_id",
        "reportstopayrollid": "reports_to_payroll_id",
        "reports_to_payroll_id": "reports_to_payroll_id",
        "hiredate": "hire_date",
        "hire_date": "hire_date",
        "temporarypassword": "temporary_password",
        "temporary_password": "temporary_password",
        "isactive": "is_active",
        "is_active": "is_active",
    }
    return aliases.get(cleaned, cleaned)


def parse_employee_import_csv(uploaded_file) -> list[dict]:
    try:
        csv_text = uploaded_file.read().decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("CSV file must be UTF-8 encoded.") from exc

    reader = csv.DictReader(StringIO(csv_text))
    if not reader.fieldnames:
        raise ValueError("CSV file must include a header row.")

    normalized_fieldnames = {
        normalize_csv_column_name(fieldname): fieldname for fieldname in reader.fieldnames
    }
    required_columns = {"first_name", "last_name", "email", "personal_leave"}
    missing_columns = [column for column in required_columns if column not in normalized_fieldnames]
    if missing_columns:
        raise ValueError(
            "CSV is missing required columns: " + ", ".join(sorted(missing_columns))
        )

    rows = []
    for line_number, raw_row in enumerate(reader, start=2):
        if not raw_row or not any((value or "").strip() for value in raw_row.values()):
            continue

        row = {
            normalize_csv_column_name(column_name): (value or "").strip()
            for column_name, value in raw_row.items()
        }
        rows.append(
            {
                "line_number": line_number,
                "first_name": row.get("first_name", ""),
                "last_name": row.get("last_name", ""),
                "email": row.get("email", ""),
                "user_id": row.get("user_id", ""),
                "payroll_id": row.get("payroll_id", ""),
                "department_id": row.get("department_id", ""),
                "department_name": row.get("department_name", ""),
                "role_name": row.get("role_name", "User") or "User",
                "personal_leave": row.get("personal_leave", ""),
                "reports_to_user_id": row.get("reports_to_user_id", ""),
                "reports_to_payroll_id": row.get("reports_to_payroll_id", ""),
                "hire_date": row.get("hire_date", ""),
                "temporary_password": row.get("temporary_password", ""),
                "is_active": row.get("is_active", ""),
            }
        )

    if not rows:
        raise ValueError("CSV file does not contain any employee rows.")

    return rows


def normalize_import_hire_date(value: str) -> str:
    raw_value = (value or "").strip()
    if not raw_value:
        return ""

    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y"):
        try:
            return datetime.strptime(raw_value, fmt).date().isoformat()
        except ValueError:
            continue

    raise ValueError(
        f"Hire date '{raw_value}' is invalid. Use YYYY-MM-DD or M/D/YYYY."
    )


def fetch_supervisor_lookup(cursor):
    cursor.execute(
        """
        SELECT
            E.EmployeeId,
            E.PayrollId,
            E.UserId
        FROM dbo.Employees E
        INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
        WHERE E.IsActive = 'Yes'
          AND R.RoleName IN ('Owner', 'Executive Director', 'Director', 'Manager')
        """
    )
    rows = cursor.fetchall()
    by_payroll_id = {str(row.PayrollId): row.UserId for row in rows}
    by_user_id = {str(row.UserId).strip().lower(): row.UserId for row in rows if row.UserId}
    return by_payroll_id, by_user_id


def fetch_employee_import_lookup(cursor):
    cursor.execute(
        """
        SELECT
            EmployeeId,
            PayrollId,
            DepartmentId,
            Email,
            UserId,
            IsActive
        FROM dbo.Employees
        """
    )
    rows = cursor.fetchall()
    by_payroll_id = {str(row.PayrollId): row for row in rows}
    by_email = {str(row.Email).strip().lower(): row for row in rows if row.Email}
    by_user_id = {str(row.UserId).strip().lower(): row for row in rows if row.UserId}
    return by_payroll_id, by_email, by_user_id


def find_employee_by_payroll_id(cursor, payroll_id: str):
    normalized_payroll_id = (payroll_id or "").strip()
    if not normalized_payroll_id:
        return None
    cursor.execute(
        """
        SELECT
            EmployeeId,
            PayrollId,
            FirstName,
            LastName,
            Email,
            UserId
        FROM dbo.Employees
        WHERE PayrollId = ?
        LIMIT 1
        """,
        normalized_payroll_id,
    )
    return cursor.fetchone()


def overwrite_employee_payroll_id(cursor, employee_id: int, payroll_id: str):
    normalized_payroll_id = (payroll_id or "").strip()
    if not normalized_payroll_id:
        return

    existing_employee = find_employee_by_payroll_id(cursor, normalized_payroll_id)
    if existing_employee is not None and existing_employee.EmployeeId != employee_id:
        raise ValueError(
            "Payroll ID "
            f"{normalized_payroll_id} is already assigned to "
            f"{existing_employee.FirstName} {existing_employee.LastName} "
            f"(Employee {existing_employee.EmployeeId})."
        )

    cursor.execute(
        """
        UPDATE dbo.Employees
        SET PayrollId = ?
        WHERE EmployeeId = ?
        """,
        normalized_payroll_id,
        employee_id,
    )


def find_employee_duplicate(cursor, email: str, user_id: str, exclude_employee_id: Optional[int] = None):
    conditions = []
    parameters = []

    if email:
        conditions.append("LOWER(Email) = ?")
        parameters.append(email.strip().lower())
    if user_id:
        conditions.append("LOWER(UserId) = ?")
        parameters.append(user_id.strip().lower())

    if not conditions:
        return None

    sql = f"""
        SELECT TOP 1
            EmployeeId,
            PayrollId,
            FirstName,
            LastName,
            Email,
            UserId
        FROM dbo.Employees
        WHERE ({' OR '.join(conditions)})
    """

    if exclude_employee_id is not None:
        sql += " AND EmployeeId <> ?"
        parameters.append(exclude_employee_id)

    sql += " ORDER BY EmployeeId"
    cursor.execute(sql, *parameters)
    return cursor.fetchone()


def fetch_employee_by_id(cursor, employee_id: int):
    cursor.execute(
        """
        SELECT
            E.EmployeeId,
            E.PayrollId,
            E.FirstName,
            E.LastName,
            E.Email,
            E.UserId,
            E.ReportsToUserId,
            E.RoleId,
            R.RoleName,
            E.IsActive
        FROM dbo.Employees E
        INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
        WHERE E.EmployeeId = ?
        """,
        employee_id,
    )
    return cursor.fetchone()


def fetch_employee_user_id(cursor, employee_id: int) -> Optional[str]:
    cursor.execute(
        """
        SELECT UserId
        FROM dbo.Employees
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    row = cursor.fetchone()
    return (row.UserId or "").strip() if row is not None and row.UserId else None


def canonicalize_existing_employee_identifiers(cursor, employee_id: int):
    employee = fetch_employee_by_id(cursor, employee_id)
    if employee is None:
        return None

    current_user_id = (employee.UserId or "").strip()
    normalized_user_id = normalize_user_id_candidate(current_user_id)
    if normalized_user_id and normalized_user_id != current_user_id:
        reassign_employee_reports(cursor, current_user_id, normalized_user_id)
        cursor.execute(
            """
            UPDATE dbo.Employees
            SET UserId = ?
            WHERE EmployeeId = ?
            """,
            normalized_user_id,
            employee_id,
        )
        employee = fetch_employee_by_id(cursor, employee_id)

    reports_to_user_id = (getattr(employee, "ReportsToUserId", None) or "").strip() if employee is not None else ""
    if reports_to_user_id:
        normalized_reports_to = normalize_user_id_candidate(reports_to_user_id)
        if normalized_reports_to and normalized_reports_to != reports_to_user_id:
            cursor.execute(
                """
                SELECT EmployeeId, UserId
                FROM dbo.Employees
                WHERE LOWER(UserId) = ?
                LIMIT 1
                """,
                normalized_reports_to,
            )
            resolved_supervisor = cursor.fetchone()
            if resolved_supervisor is not None:
                cursor.execute(
                    """
                    UPDATE dbo.Employees
                    SET ReportsToUserId = ?
                    WHERE EmployeeId = ?
                    """,
                    resolved_supervisor.UserId,
                    employee_id,
                )
                employee = fetch_employee_by_id(cursor, employee_id)

    return employee


def repair_all_employee_identifiers(cursor) -> dict:
    cursor.execute(
        """
        SELECT EmployeeId
        FROM dbo.Employees
        ORDER BY EmployeeId
        """
    )
    employee_ids = [row.EmployeeId for row in cursor.fetchall()]
    repaired_user_ids = 0
    repaired_reports_to = 0

    for employee_id in employee_ids:
        before = fetch_employee_by_id(cursor, employee_id)
        if before is None:
            continue
        before_user_id = (before.UserId or "").strip()
        before_reports_to = (getattr(before, "ReportsToUserId", None) or "").strip()

        after = canonicalize_existing_employee_identifiers(cursor, employee_id)
        if after is None:
            continue
        after_user_id = (after.UserId or "").strip()
        after_reports_to = (getattr(after, "ReportsToUserId", None) or "").strip()

        if before_user_id != after_user_id:
            repaired_user_ids += 1
        if before_reports_to != after_reports_to:
            repaired_reports_to += 1

    return {
        "repaired_user_ids": repaired_user_ids,
        "repaired_reports_to": repaired_reports_to,
    }


def make_employee_inactive(cursor, employee_id: int) -> bool:
    cursor.execute(
        """
        UPDATE dbo.Employees
        SET IsActive = 'No'
        WHERE EmployeeId = ?
          AND IsActive <> 'No'
        """,
        employee_id,
    )
    return cursor.rowcount > 0


def reassign_employee_reports(cursor, previous_user_id: str, next_user_id: Optional[str]):
    normalized_previous = (previous_user_id or "").strip()
    if not normalized_previous:
        return

    if next_user_id:
        cursor.execute(
            """
            UPDATE dbo.Employees
            SET ReportsToUserId = ?
            WHERE ReportsToUserId = ?
            """,
            next_user_id.strip(),
            normalized_previous,
        )
        return

    cursor.execute(
        """
        UPDATE dbo.Employees
        SET ReportsToUserId = NULL
        WHERE ReportsToUserId = ?
        """,
        normalized_previous,
    )


def resolve_supervisor_form_value(cursor, employee_id_value: str, user_id_value: Optional[str]) -> Optional[str]:
    selected_employee_id = (employee_id_value or "").strip()
    if selected_employee_id:
        try:
            selected_supervisor_id = int(selected_employee_id)
        except ValueError as exc:
            raise ValueError("Workflow supervisor selection is invalid.") from exc
        resolved_user_id = fetch_employee_user_id(cursor, selected_supervisor_id)
        if not resolved_user_id:
            raise ValueError("Workflow supervisor was not found.")
        return resolved_user_id

    normalized_user_id = (user_id_value or "").strip()
    return normalized_user_id or None


def delete_employee_records(conn, cursor, employee_id: int):
    ensure_password_setup_schema(conn)
    employee = fetch_employee_by_id(cursor, employee_id)
    if employee is None:
        raise ValueError("Employee not found.")

    employee_user_id = (employee.UserId or "").strip()

    reassign_employee_reports(cursor, employee_user_id, None)
    cursor.execute(
        """
        UPDATE dbo.LeaveRequests
        SET ApprovedByEmployeeId = NULL
        WHERE ApprovedByEmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        UPDATE dbo.FaceTemplates
        SET EnrolledByEmployeeId = NULL
        WHERE EnrolledByEmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        UPDATE dbo.TimeEntries
        SET CreatedByEmployeeId = NULL
        WHERE CreatedByEmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        UPDATE dbo.TimeEntries
        SET LastModifiedByEmployeeId = NULL
        WHERE LastModifiedByEmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        UPDATE dbo.TimeEntryAudit
        SET ChangedByEmployeeId = 1
        WHERE ChangedByEmployeeId = ?
        """,
        employee_id,
    )

    cursor.execute(
        """
        UPDATE dbo.TimeEntries
        SET VerificationAttemptId = NULL
        WHERE VerificationAttemptId IN
        (
            SELECT FaceVerificationAttemptId
            FROM dbo.FaceVerificationAttempts
            WHERE EmployeeId = ?
               OR MobileDeviceId IN
                  (
                      SELECT MobileDeviceId
                      FROM dbo.MobileDevices
                      WHERE EmployeeId = ?
                  )
        )
        """,
        employee_id,
        employee_id,
    )
    cursor.execute(
        """
        UPDATE dbo.TimeEntries
        SET SourceDeviceId = NULL
        WHERE SourceDeviceId IN
        (
            SELECT MobileDeviceId
            FROM dbo.MobileDevices
            WHERE EmployeeId = ?
        )
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.PasswordSetupTokens
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.TimeEntryAudit
        WHERE EmployeeId = ?
           OR TimeEntryId IN
              (
                  SELECT TimeEntryId
                  FROM dbo.TimeEntries
                  WHERE EmployeeId = ?
              )
        """,
        employee_id,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.LeaveLedger
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.LeaveRequests
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.FaceVerificationAttempts
        WHERE EmployeeId = ?
           OR MobileDeviceId IN
              (
                  SELECT MobileDeviceId
                  FROM dbo.MobileDevices
                  WHERE EmployeeId = ?
              )
        """,
        employee_id,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.FaceTemplates
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.MobileDevices
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.TimeEntries
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    cursor.execute(
        """
        DELETE FROM dbo.Employees
        WHERE EmployeeId = ?
        """,
        employee_id,
    )
    if cursor.rowcount <= 0:
        raise ValueError("Employee could not be deleted.")

    return employee


def fetch_departments():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT DepartmentId, DepartmentName
            FROM dbo.Departments
            ORDER BY DepartmentId
            """
        )
        return cursor.fetchall()


def create_department(cursor, department_id: int, department_name: str):
    cursor.execute(
        """
        INSERT INTO dbo.Departments (DepartmentId, DepartmentName)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
            DepartmentName = VALUES(DepartmentName)
        """,
        department_id,
        department_name,
    )


def resolve_supervisor_user_id(
    row: dict,
    supervisor_user_ids_by_payroll_id: dict[str, str],
    supervisor_user_ids_by_user_id: dict[str, str],
) -> Optional[str]:
    reports_to_payroll_id = row.get("reports_to_payroll_id", "").strip()
    reports_to_user_id = row["reports_to_user_id"].strip().lower()

    if not reports_to_payroll_id and not reports_to_user_id:
        return None

    resolved_from_payroll_id = None
    resolved_from_user_id = None

    if reports_to_payroll_id:
        resolved_from_payroll_id = supervisor_user_ids_by_payroll_id.get(reports_to_payroll_id)
        if resolved_from_payroll_id is None:
            raise ValueError(
                f"Workflow payroll ID '{reports_to_payroll_id}' was not found in the active supervisor list."
            )

    if reports_to_user_id:
        resolved_from_user_id = supervisor_user_ids_by_user_id.get(reports_to_user_id)
        if resolved_from_user_id is None:
            raise ValueError(
                f"Workflow user ID '{reports_to_user_id}' was not found in the active supervisor list."
            )

    if (
        resolved_from_payroll_id is not None
        and resolved_from_user_id is not None
        and resolved_from_payroll_id != resolved_from_user_id
    ):
        raise ValueError("Workflow payroll ID and workflow user ID point to different employees.")

    return resolved_from_payroll_id if resolved_from_payroll_id is not None else resolved_from_user_id


def resolve_department_id(row: dict, departments_by_id: dict[str, int], departments_by_name: dict[str, int]) -> int:
    department_id_value = row.get("department_id", "").strip()
    department_name_value = row.get("department_name", "").strip().lower()
    payroll_id_value = row.get("payroll_id", "").strip()

    resolved_from_id = None
    resolved_from_name = None
    resolved_from_payroll = None

    if department_id_value:
        resolved_from_id = departments_by_id.get(department_id_value)
        if resolved_from_id is None:
            raise ValueError(f"Funding ID '{department_id_value}' was not found.")

    if department_name_value:
        resolved_from_name = departments_by_name.get(department_name_value)
        if resolved_from_name is None:
            raise ValueError(f"Funding source '{row.get('department_name', '')}' was not found.")

    if payroll_id_value and len(payroll_id_value) >= 2 and payroll_id_value[:2].isdigit():
        resolved_from_payroll = departments_by_id.get(payroll_id_value[:2])

    if resolved_from_id is not None and resolved_from_name is not None and resolved_from_id != resolved_from_name:
        raise ValueError("Funding ID and funding source point to different funding sources.")

    if (
        resolved_from_id is not None
        and resolved_from_payroll is not None
        and resolved_from_id != resolved_from_payroll
    ):
        raise ValueError("Funding ID and payroll ID point to different funding sources.")
    if (
        resolved_from_name is not None
        and resolved_from_payroll is not None
        and resolved_from_name != resolved_from_payroll
    ):
        raise ValueError("Funding source and payroll ID point to different funding sources.")

    resolved_value = (
        resolved_from_id
        if resolved_from_id is not None
        else resolved_from_name
        if resolved_from_name is not None
        else resolved_from_payroll
    )
    if resolved_value is None:
        raise ValueError("Funding source is required.")
    return resolved_value


def can_manage_clock_for_target(target_employee_id: int, viewer_employee_id: int, role_name: str) -> bool:
    if role_name not in CLOCK_MANAGEMENT_ROLES:
        return False
    if target_employee_id == viewer_employee_id:
        return role_name in CLOCK_SELF_ROLES
    return can_access_employee(target_employee_id, viewer_employee_id, role_name)


def ensure_timesheet_admin_schema(conn):
    return


def parse_local_datetime(value: str, field_label: str) -> datetime:
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M")
    except (TypeError, ValueError):
        raise ValueError(f"{field_label} is not a valid date and time.")


def fetch_timesheet_rows(cursor, employee_id: int, period_start: date):
    period_end = period_start + timedelta(days=13)
    cursor.execute(
        """
        SELECT
            TimeEntryId,
            CAST(ClockInTime AS DATE) AS WorkDate,
            ClockInTime,
            ClockOutTime,
            CAST(
                CASE
                    WHEN ClockOutTime IS NULL THEN 0
                    ELSE DATEDIFF(MINUTE, ClockInTime, ClockOutTime) / 60.0
                END
                AS DECIMAL(8,2)
            ) AS WorkedHours,
            Notes,
            ISNULL(EntrySource, 'Clock') AS EntrySource
        FROM dbo.TimeEntries
        WHERE EmployeeId = ?
          AND CAST(ClockInTime AS DATE) BETWEEN ? AND ?
        ORDER BY ClockInTime
        """,
        employee_id,
        period_start,
        period_end,
    )
    return cursor.fetchall()


def fetch_time_entry_with_employee(cursor, time_entry_id: int):
    cursor.execute(
        """
        SELECT
            T.TimeEntryId,
            T.EmployeeId,
            LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
            T.ClockInTime,
            T.ClockOutTime,
            T.Notes,
            ISNULL(T.EntrySource, 'Clock') AS EntrySource
        FROM dbo.TimeEntries T
        INNER JOIN dbo.Employees E ON E.EmployeeId = T.EmployeeId
        WHERE T.TimeEntryId = ?
        """,
        time_entry_id,
    )
    return cursor.fetchone()


def fetch_time_entry_audit(cursor, time_entry_id: int):
    cursor.execute(
        """
        SELECT
            A.TimeEntryAuditId,
            A.ActionType,
            A.ChangeReason,
            A.OldClockInTime,
            A.NewClockInTime,
            A.OldClockOutTime,
            A.NewClockOutTime,
            A.OldNotes,
            A.NewNotes,
            ISNULL(A.OldEntrySource, 'Clock') AS OldEntrySource,
            ISNULL(A.NewEntrySource, 'Clock') AS NewEntrySource,
            A.ChangedAt,
            LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS ChangedByFullName
        FROM dbo.TimeEntryAudit A
        INNER JOIN dbo.Employees E ON E.EmployeeId = A.ChangedByEmployeeId
        WHERE A.TimeEntryId = ?
        ORDER BY A.ChangedAt DESC, A.TimeEntryAuditId DESC
        """,
        time_entry_id,
    )
    return cursor.fetchall()


def write_time_entry_audit(
    cursor,
    *,
    time_entry_id: int,
    employee_id: int,
    action_type: str,
    changed_by_employee_id: int,
    change_reason: str,
    old_clock_in_time,
    new_clock_in_time,
    old_clock_out_time,
    new_clock_out_time,
    old_notes,
    new_notes,
    old_entry_source,
    new_entry_source,
):
    cursor.execute(
        """
        INSERT INTO dbo.TimeEntryAudit
        (
            TimeEntryId,
            EmployeeId,
            ActionType,
            ChangeReason,
            OldClockInTime,
            NewClockInTime,
            OldClockOutTime,
            NewClockOutTime,
            OldNotes,
            NewNotes,
            OldEntrySource,
            NewEntrySource,
            ChangedByEmployeeId
        )
        VALUES
        (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        )
        """,
        time_entry_id,
        employee_id,
        action_type,
        change_reason,
        old_clock_in_time,
        new_clock_in_time,
        old_clock_out_time,
        new_clock_out_time,
        old_notes,
        new_notes,
        old_entry_source,
        new_entry_source,
        changed_by_employee_id,
    )


def fetch_accessible_employees(viewer_employee_id: int, role_name: str):
    viewer_user_id = current_user_id()
    with get_connection() as conn:
        cursor = conn.cursor()
        if role_name == "Owner":
            cursor.execute(
                """
                SELECT
                    E.EmployeeId,
                    E.PayrollId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    E.UserId,
                    R.RoleName
                FROM dbo.Employees E
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                WHERE E.IsActive = 'Yes'
                ORDER BY E.LastName, E.FirstName
                """
            )
        elif role_name in TIMESHEET_REVIEW_ROLES:
            cursor.execute(
                """
                WITH EmployeeTree AS
                (
                    SELECT
                        E.EmployeeId,
                        E.PayrollId,
                        E.FirstName,
                        E.LastName,
                        E.UserId,
                        E.RoleId
                    FROM dbo.Employees E
                    WHERE E.ReportsToUserId = ?
                      AND E.IsActive = 'Yes'

                    UNION ALL

                    SELECT
                        E.EmployeeId,
                        E.PayrollId,
                        E.FirstName,
                        E.LastName,
                        E.UserId,
                        E.RoleId
                    FROM dbo.Employees E
                    INNER JOIN EmployeeTree T ON E.ReportsToUserId = T.UserId
                    WHERE E.IsActive = 'Yes'
                )
                SELECT
                    T.EmployeeId,
                    T.PayrollId,
                    LTRIM(RTRIM(CONCAT(T.FirstName, ' ', T.LastName))) AS FullName,
                    T.UserId,
                    R.RoleName
                FROM EmployeeTree T
                INNER JOIN dbo.Roles R ON R.RoleId = T.RoleId
                ORDER BY T.LastName, T.FirstName
                """,
                viewer_user_id,
            )
        else:
            cursor.execute(
                """
                SELECT
                    E.EmployeeId,
                    E.PayrollId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    E.UserId,
                    R.RoleName
                FROM dbo.Employees E
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                WHERE E.EmployeeId = ?
                """,
                viewer_employee_id,
            )
        return cursor.fetchall()


def can_access_employee(target_employee_id: int, viewer_employee_id: int, role_name: str) -> bool:
    if target_employee_id == viewer_employee_id:
        return True
    return any(row.EmployeeId == target_employee_id for row in fetch_accessible_employees(viewer_employee_id, role_name))


def get_supervisor_choices():
    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                E.EmployeeId,
                E.PayrollId,
                E.DepartmentId,
                D.DepartmentName,
                E.UserId,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                R.RoleName
            FROM dbo.Employees E
            INNER JOIN dbo.Departments D ON D.DepartmentId = E.DepartmentId
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            WHERE E.IsActive = 'Yes'
              AND R.RoleName IN ('Owner', 'Executive Director', 'Director', 'Manager')
            ORDER BY E.LastName, E.FirstName
            """
        )
        return cursor.fetchall()


def fetch_employee_export_rows():
    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                E.EmployeeId,
                E.FirstName,
                E.LastName,
                E.Email,
                E.UserId,
                E.PayrollId,
                E.DepartmentId,
                D.DepartmentName,
                R.RoleName,
                E.PersonalLeave,
                E.ReportsToUserId,
                E.HireDate,
                E.IsActive
            FROM dbo.Employees E
            INNER JOIN dbo.Departments D ON D.DepartmentId = E.DepartmentId
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            ORDER BY E.LastName, E.FirstName
            """
        )
        return cursor.fetchall()


def fetch_manual_leave_employees():
    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                E.EmployeeId,
                E.PayrollId,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                E.PersonalLeave AS IsHeadStart,
                R.RoleName
            FROM dbo.Employees E
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            WHERE E.IsActive = 'Yes'
            ORDER BY E.LastName, E.FirstName
            """
        )
        return cursor.fetchall()


def fetch_user_summary(employee_id: int):
    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                E.EmployeeId,
                E.PayrollId,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                E.Email,
                E.UserId,
                E.PersonalLeave AS IsHeadStart,
                R.RoleName,
                E.HireDate,
                IFNULL(B.AnnualLeaveHours, 0) AS AnnualLeaveHours,
                IFNULL(B.SickLeaveHours, 0) AS SickLeaveHours,
                IFNULL(B.PersonalLeaveHours, 0) AS PersonalLeaveHours,
                D.DepartmentName
            FROM dbo.Employees E
            INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
            INNER JOIN dbo.Departments D ON D.DepartmentId = E.DepartmentId
            LEFT JOIN dbo.vw_EmployeeLeaveBalances B ON B.EmployeeId = E.EmployeeId
            WHERE E.EmployeeId = ?
            """,
            employee_id,
        )
        row = cursor.fetchone()
        if not row:
            return None

        cursor.execute(
            """
            SELECT TOP 1 TimeEntryId, ClockInTime
            FROM dbo.TimeEntries
            WHERE EmployeeId = ? AND ClockOutTime IS NULL
            ORDER BY ClockInTime DESC
            """,
            employee_id,
        )
        open_entry = cursor.fetchone()

        cursor.execute(
            """
            SELECT TOP 5
                LeaveRequestId,
                LeaveType,
                StartDate,
                EndDate,
                RequestedHours,
                ApprovalStatus
            FROM dbo.LeaveRequests
            WHERE EmployeeId = ?
            ORDER BY RequestedAt DESC
            """,
            employee_id,
        )
        leave_requests = cursor.fetchall()

        return {
            "employee_id": row.EmployeeId,
            "payroll_id": row.PayrollId,
            "full_name": row.FullName,
            "email": row.Email,
            "user_id": row.UserId,
            "department_name": row.DepartmentName,
            "is_head_start": bool(row.IsHeadStart),
            "role_name": row.RoleName,
            "hire_date": row.HireDate,
            "annual_leave_hours": float(row.AnnualLeaveHours or 0),
            "sick_leave_hours": float(row.SickLeaveHours or 0),
            "personal_leave_hours": float(row.PersonalLeaveHours or 0),
            "clocked_in": open_entry is not None,
            "open_clock_in_time": open_entry.ClockInTime if open_entry else None,
            "leave_requests": leave_requests,
        }


def get_biweekly_period(anchor: Optional[date] = None):
    today = anchor or date.today()
    days_since_sunday = (today.weekday() + 1) % 7
    start = today - timedelta(days=days_since_sunday)
    start = start - timedelta(days=7)
    end = start + timedelta(days=13)
    return start, end


def build_available_timesheet_periods(hire_date: Optional[date], current_period_start: date) -> list[dict]:
    first_available_start = current_period_start
    if hire_date:
        first_available_start, _ = get_biweekly_period(hire_date)

    periods = []
    period_start = current_period_start
    while period_start >= first_available_start:
        period_end = period_start + timedelta(days=13)
        periods.append(
            {
                "value": period_start.isoformat(),
                "label": f"{format_date_mmddyyyy(period_start)} - {format_date_mmddyyyy(period_end)}",
            }
        )
        period_start -= timedelta(days=14)
    return periods


def ensure_biweekly_leave_accruals(conn, anchor: Optional[date] = None):
    today = anchor or date.today()
    if today < PAY_PERIOD_END_ANCHOR:
        return

    days_since_anchor = (today - PAY_PERIOD_END_ANCHOR).days
    latest_completed_period_end = PAY_PERIOD_END_ANCHOR + timedelta(days=(days_since_anchor // 14) * 14)
    cursor = conn.cursor()
    period_end = PAY_PERIOD_END_ANCHOR
    while period_end <= latest_completed_period_end:
        period_start = period_end - timedelta(days=13)
        accrual_note = f"Bi-weekly accrual for {period_start.isoformat()} through {period_end.isoformat()}"
        cursor.execute(
            """
            SELECT LeaveLedgerId
            FROM dbo.LeaveLedger
            WHERE EntryReason = 'Accrual'
              AND EntryDate = ?
              AND Notes = ?
            LIMIT 1
            """,
            period_end,
            accrual_note,
        )
        if not cursor.fetchone():
            cursor.execute(
                """
                INSERT INTO dbo.LeaveLedger (EmployeeId, EntryDate, LeaveType, Hours, EntryReason, Notes)
                SELECT
                    E.EmployeeId,
                    ?,
                    'Sick',
                    ROUND((dbo.fn_GetMonthlyAccrualHours(E.HireDate) * 12.0) / 26.0, 2),
                    'Accrual',
                    ?
                FROM dbo.Employees E
                WHERE E.IsActive = 'Yes'
                  AND E.HireDate <= ?
                UNION ALL
                SELECT
                    E.EmployeeId,
                    ?,
                    CASE WHEN E.PersonalLeave = 1 THEN 'Personal' ELSE 'Annual' END,
                    ROUND((dbo.fn_GetMonthlyAccrualHours(E.HireDate) * 12.0) / 26.0, 2),
                    'Accrual',
                    ?
                FROM dbo.Employees E
                WHERE E.IsActive = 'Yes'
                  AND E.HireDate <= ?
                """,
                period_end,
                accrual_note,
                period_end,
                period_end,
                accrual_note,
                period_end,
            )
        period_end += timedelta(days=14)
    conn.commit()


@app.route("/", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form["email"].strip().lower()
        password = request.form["password"]

        with get_connection() as conn:
            ensure_role_catalog(conn)
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    E.EmployeeId,
                    E.PayrollId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    E.Email,
                    E.UserId,
                    E.PasswordSalt,
                    E.PasswordHash,
                    E.MustChangePassword,
                    R.RoleName
                FROM dbo.Employees E
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                WHERE E.Email = ? AND E.IsActive = 'Yes'
                """,
                email,
            )
            user = cursor.fetchone()

        if not user or hash_password(user.PasswordSalt, password) != user.PasswordHash:
            flash("Invalid email or password.", "error")
            return render_template("login.html")

        session["user"] = {
            "employee_id": user.EmployeeId,
            "payroll_id": user.PayrollId,
            "full_name": user.FullName,
            "email": user.Email,
            "user_id": user.UserId,
        }
        session["role_name"] = user.RoleName
        session.permanent = True
        session["last_biweekly_accrual_check"] = ""

        if user.MustChangePassword and not is_seeded_owner_account(user):
            flash("Create a new password before continuing.", "info")
            return redirect(url_for("change_password"))

        return redirect(url_for("dashboard"))

    return render_template("login.html")


@app.route("/forgot-password", methods=["GET", "POST"])
def forgot_password():
    if not invitations_enabled():
        flash(
            "Password setup emails are disabled while the app is being tuned. Contact the Owner for a setup link.",
            "info",
        )
        return redirect(url_for("login"))

    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        generic_message = (
            "If an active account exists for that email address, a one-time password setup link has been sent."
        )

        if not email:
            flash("Enter your email address to reset your password.", "error")
            return render_template(
                "forgot_password.html",
                email_configured=password_reset_email_is_configured(),
            )

        if not password_reset_email_is_configured():
            flash(
                "Password reset email is not configured yet. Contact your administrator.",
                "error",
            )
            return render_template("forgot_password.html", email=email, email_configured=False)

        with get_connection() as conn:
            ensure_role_catalog(conn)
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT TOP 1
                    EmployeeId,
                    LTRIM(RTRIM(CONCAT(FirstName, ' ', LastName))) AS FullName,
                    Email
                FROM dbo.Employees
                WHERE Email = ? AND IsActive = 'Yes'
                """,
                email,
            )
            employee = cursor.fetchone()

            if not employee:
                flash(generic_message, "info")
                return redirect(url_for("login"))

            setup_link = create_password_setup_link(conn, employee.EmployeeId, "Reset")
            try:
                send_password_setup_email(
                    recipient_email=employee.Email,
                    recipient_name=employee.FullName,
                    setup_link=setup_link,
                )
            except Exception:
                conn.rollback()
                flash(
                    "We could not send the password setup email right now. Please try again or contact your administrator.",
                    "error",
                )
                return render_template(
                    "forgot_password.html",
                    email=email,
                    email_configured=True,
                )

            conn.commit()

        flash(generic_message, "success")
        return redirect(url_for("login"))

    return render_template(
        "forgot_password.html",
        email_configured=password_reset_email_is_configured(),
    )


@app.route("/change-password", methods=["GET", "POST"])
@login_required
def change_password():
    if request.method == "POST":
        new_password = request.form["new_password"]
        confirm_password = request.form["confirm_password"]

        complexity_error = validate_password_complexity(new_password)
        if complexity_error:
            flash(complexity_error, "error")
            return render_template("change_password.html")

        if new_password != confirm_password:
            flash("Passwords do not match.", "error")
            return render_template("change_password.html")

        new_salt = os.urandom(8).hex().upper()
        new_hash = hash_password(new_salt, new_password)

        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                UPDATE dbo.Employees
                SET PasswordSalt = ?, PasswordHash = ?, MustChangePassword = 0
                WHERE EmployeeId = ?
                """,
                new_salt,
                new_hash,
                session["user"]["employee_id"],
            )
            conn.commit()

        flash("Password updated successfully.", "success")
        return redirect(url_for("dashboard"))

    return render_template("change_password.html")


@app.route("/set-password/<token>", methods=["GET", "POST"])
def set_password(token: str):
    token_hash = hash_setup_token(token)

    with get_connection() as conn:
        ensure_password_setup_schema(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                PST.PasswordSetupTokenId,
                PST.EmployeeId,
                PST.ExpiresAt,
                PST.UsedAt,
                LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                E.Email
            FROM dbo.PasswordSetupTokens PST
            INNER JOIN dbo.Employees E ON E.EmployeeId = PST.EmployeeId
            WHERE PST.TokenHash = ?
            LIMIT 1
            """,
            token_hash,
        )
        token_row = cursor.fetchone()

        if not token_row or token_row.UsedAt is not None or token_row.ExpiresAt < datetime.utcnow():
            flash("That password setup link is invalid or has expired.", "error")
            return redirect(url_for("login"))

        if request.method == "POST":
            new_password = request.form["new_password"]
            confirm_password = request.form["confirm_password"]

            complexity_error = validate_password_complexity(new_password)
            if complexity_error:
                flash(complexity_error, "error")
                return render_template("change_password.html", token=token, setup_mode=True)

            if new_password != confirm_password:
                flash("Passwords do not match.", "error")
                return render_template("change_password.html", token=token, setup_mode=True)

            new_salt = os.urandom(8).hex().upper()
            new_hash = hash_password(new_salt, new_password)
            cursor.execute(
                """
                UPDATE dbo.Employees
                SET PasswordSalt = ?, PasswordHash = ?, MustChangePassword = 0
                WHERE EmployeeId = ?
                """,
                new_salt,
                new_hash,
                token_row.EmployeeId,
            )
            cursor.execute(
                """
                UPDATE dbo.PasswordSetupTokens
                SET UsedAt = UTC_TIMESTAMP(6)
                WHERE PasswordSetupTokenId = ?
                """,
                token_row.PasswordSetupTokenId,
            )
            conn.commit()

            flash("Password created successfully. You can sign in now.", "success")
            return redirect(url_for("login"))

    return render_template("change_password.html", token=token, setup_mode=True)


@app.route("/dashboard")
@login_required
def dashboard():
    summary = fetch_user_summary(session["user"]["employee_id"])
    period_start, period_end = get_biweekly_period()
    return render_template(
        "dashboard.html",
        summary=summary,
        can_self_clock=role_can(current_role_name(), CLOCK_SELF_ROLES),
        can_manual_leave_entry=role_can(current_role_name(), MANUAL_LEAVE_ENTRY_ROLES),
        period_start=period_start,
        period_end=period_end,
    )


@app.route("/clock-in", methods=["POST"])
@login_required
def clock_in():
    if not role_can(current_role_name(), CLOCK_SELF_ROLES):
        flash("Your role cannot clock in from the GUI.", "error")
        return redirect(url_for("dashboard"))

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "EXEC dbo.usp_ClockIn @EmployeeId = ?",
            session["user"]["employee_id"],
        )
        conn.commit()

    flash("Clock-in recorded.", "success")
    return redirect(url_for("dashboard"))


@app.route("/clock-out", methods=["POST"])
@login_required
def clock_out():
    if not role_can(current_role_name(), CLOCK_SELF_ROLES):
        flash("Your role cannot clock out from the GUI.", "error")
        return redirect(url_for("dashboard"))

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "EXEC dbo.usp_ClockOut @EmployeeId = ?",
            session["user"]["employee_id"],
        )
        conn.commit()

    flash("Clock-out recorded.", "success")
    return redirect(url_for("dashboard"))


@app.route("/request-leave", methods=["POST"])
@login_required
def request_leave():
    leave_type = request.form["leave_type"]
    start_date = request.form["start_date"]
    end_date = request.form["end_date"]
    requested_hours = request.form["requested_hours"]
    notes = request.form.get("notes", "").strip()

    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            EXEC dbo.usp_RequestLeave
                @EmployeeId = ?,
                @LeaveType = ?,
                @StartDate = ?,
                @EndDate = ?,
                @RequestedHours = ?,
                @Notes = ?
            """,
            session["user"]["employee_id"],
            leave_type,
            start_date,
            end_date,
            requested_hours,
            notes or None,
        )
        conn.commit()

    flash("Leave request submitted.", "success")
    return redirect(url_for("dashboard"))


@app.route("/leave/<int:leave_request_id>/cancel", methods=["POST"])
@login_required
def cancel_leave_request(leave_request_id: int):
    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            EXEC dbo.usp_CancelLeaveRequest
                @LeaveRequestId = ?,
                @EmployeeId = ?
            """,
            leave_request_id,
            current_employee_id(),
        )
        conn.commit()

    flash("Leave request cancelled.", "success")
    return redirect(url_for("dashboard"))


@app.route("/timesheet")
@login_required
def timesheet():
    viewer_id = current_employee_id()
    viewer_role = current_role_name()
    requested_employee_id = request.args.get("employee_id", type=int)
    target_employee_id = requested_employee_id or viewer_id
    if not can_access_employee(target_employee_id, viewer_id, viewer_role):
        flash("You do not have access to that employee timesheet.", "error")
        return redirect(url_for("dashboard"))

    period_start_arg = request.args.get("period_start")
    if period_start_arg:
        requested_date = datetime.strptime(period_start_arg, "%Y-%m-%d").date()
        period_start, period_end = get_biweekly_period(requested_date)
    else:
        period_start, period_end = get_biweekly_period()
    current_period_start, _ = get_biweekly_period()
    previous_period_start = period_start - timedelta(days=14)
    next_period_start = period_start + timedelta(days=14)
    if next_period_start > current_period_start:
        next_period_start = None

    summary = fetch_user_summary(target_employee_id)
    available_periods = build_available_timesheet_periods(summary.get("hire_date"), current_period_start)
    with get_connection() as conn:
        ensure_timesheet_admin_schema(conn)
        cursor = conn.cursor()
        rows = fetch_timesheet_rows(cursor, target_employee_id, period_start)

    total_hours = sum(float(row.WorkedHours or 0) for row in rows)
    return render_template(
        "timesheet.html",
        summary=summary,
        can_edit_times=viewer_role in TIME_EDIT_ROLES and target_employee_id != viewer_id and can_access_employee(target_employee_id, viewer_id, viewer_role),
        rows=rows,
        total_hours=total_hours,
        period_start=period_start,
        period_end=period_end,
        previous_period_start=previous_period_start,
        next_period_start=next_period_start,
        current_period_start=current_period_start,
        available_periods=available_periods,
    )


@app.route("/timesheet/print")
@login_required
def print_timesheet():
    viewer_id = current_employee_id()
    viewer_role = current_role_name()
    requested_employee_id = request.args.get("employee_id", type=int)
    target_employee_id = requested_employee_id or viewer_id
    if not can_access_employee(target_employee_id, viewer_id, viewer_role):
        flash("You do not have access to that employee timesheet.", "error")
        return redirect(url_for("dashboard"))

    period_start_arg = request.args.get("period_start")
    if period_start_arg:
        requested_date = datetime.strptime(period_start_arg, "%Y-%m-%d").date()
        period_start, _ = get_biweekly_period(requested_date)
    else:
        period_start, _ = get_biweekly_period()

    summary = fetch_user_summary(target_employee_id)

    with get_connection() as conn:
        ensure_timesheet_admin_schema(conn)
        cursor = conn.cursor()
        rows = fetch_timesheet_rows(cursor, target_employee_id, period_start)

    total_hours = sum(float(row.WorkedHours or 0) for row in rows)
    lines = [
        "Mississippi County, Arkansas",
        "Economic Opprtunity Commision",
        "Employee Timesheet",
        "",
        f"Employee Name: {summary['full_name']}",
        f"Employee ID: {summary['employee_id']}",
        f"Pay Period: {format_date_mmddyyyy(period_start)} - {format_date_mmddyyyy(period_start + timedelta(days=13))}",
        f"Sick Leave Available: {summary['sick_leave_hours']:.2f}",
        f"Annual Leave Available: {summary['annual_leave_hours']:.2f}",
        "",
        "Work Date | Clock In | Clock Out | Hours | Notes / Source",
        "-" * 100,
    ]
    if summary["is_head_start"]:
        lines.insert(9, f"Personal Time Available: {summary['personal_leave_hours']:.2f}")
    for row in rows:
        lines.append(
            f"{format_date_mmddyyyy(row.WorkDate)} | {format_time_12h(row.ClockInTime)} | {format_clock_boundary(row.ClockInTime, row.ClockOutTime)} | {row.WorkedHours} | {(row.Notes or '').strip() or row.EntrySource}"
        )
    lines.extend([
        "",
        f"Total Hours: {total_hours:.2f}"
    ])

    buffer = BytesIO("\n".join(lines).encode("utf-8"))
    return send_file(
        buffer,
        mimetype="text/plain",
        as_attachment=True,
        download_name=f"timesheet_{period_start.isoformat()}.txt",
    )


@app.route("/timesheet/export-pdf")
@login_required
def export_timesheet_pdf():
    viewer_id = current_employee_id()
    viewer_role = current_role_name()
    requested_employee_id = request.args.get("employee_id", type=int)
    target_employee_id = requested_employee_id or viewer_id
    if not can_access_employee(target_employee_id, viewer_id, viewer_role):
        flash("You do not have access to that employee timesheet.", "error")
        return redirect(url_for("dashboard"))

    period_start_arg = request.args.get("period_start")
    if period_start_arg:
        requested_date = datetime.strptime(period_start_arg, "%Y-%m-%d").date()
        period_start, _ = get_biweekly_period(requested_date)
    else:
        period_start, _ = get_biweekly_period()
    period_end = period_start + timedelta(days=13)

    summary = fetch_user_summary(target_employee_id)

    with get_connection() as conn:
        ensure_timesheet_admin_schema(conn)
        cursor = conn.cursor()
        rows = fetch_timesheet_rows(cursor, target_employee_id, period_start)

    total_hours = sum(float(row.WorkedHours or 0) for row in rows)
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        leftMargin=0.55 * inch,
        rightMargin=0.55 * inch,
        topMargin=0.6 * inch,
        bottomMargin=0.6 * inch,
    )
    styles = getSampleStyleSheet()
    story = []

    header_style = styles["Heading2"].clone("TimesheetHeader")
    header_style.alignment = 1
    header_style.fontName = "Helvetica-Bold"
    header_style.fontSize = 14
    header_style.leading = 16
    header_style.spaceAfter = 2

    subheader_style = styles["Heading3"].clone("TimesheetSubheader")
    subheader_style.alignment = 1
    subheader_style.fontName = "Helvetica-Bold"
    subheader_style.fontSize = 12
    subheader_style.leading = 14
    subheader_style.spaceAfter = 2

    title_style = styles["BodyText"].clone("TimesheetTitle")
    title_style.alignment = 1
    title_style.fontName = "Helvetica-Bold"
    title_style.fontSize = 11
    title_style.leading = 13
    title_style.spaceAfter = 10

    meta_style = styles["BodyText"].clone("TimesheetMeta")
    meta_style.fontName = "Helvetica"
    meta_style.fontSize = 10
    meta_style.leading = 12

    story.append(Paragraph("Mississippi County, Arkansas", header_style))
    story.append(Paragraph("Economic Opprtunity Commision", subheader_style))
    story.append(Paragraph("Employee Timesheet", title_style))

    meta_data = [
        [
            Paragraph(f"<b>Employee Name:</b> {summary['full_name']}", meta_style),
            Paragraph(f"<b>Employee ID:</b> {summary['employee_id']}", meta_style),
        ],
        [
            Paragraph(
                f"<b>Pay Period:</b> {format_date_mmddyyyy(period_start)} - {format_date_mmddyyyy(period_end)}",
                meta_style,
            ),
            Paragraph(f"<b>Sick Leave Available:</b> {summary['sick_leave_hours']:.2f}", meta_style),
        ],
        [Paragraph(f"<b>Annual Leave Available:</b> {summary['annual_leave_hours']:.2f}", meta_style)],
    ]
    if summary["is_head_start"]:
        meta_data[-1].append(
            Paragraph(f"<b>Personal Time Available:</b> {summary['personal_leave_hours']:.2f}", meta_style)
        )
    else:
        meta_data[-1].append(Paragraph("", meta_style))
    meta_table = Table(meta_data, colWidths=[3.6 * inch, 3.25 * inch], hAlign="LEFT")
    meta_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(meta_table)
    story.append(Spacer(1, 0.18 * inch))

    table_data = [["Date", "Clock In", "Clock Out", "Hours", "Notes / Source"]]
    for row in rows:
        table_data.append(
            [
                format_date_mmddyyyy(row.WorkDate),
                format_time_12h(row.ClockInTime),
                format_clock_boundary(row.ClockInTime, row.ClockOutTime),
                f"{float(row.WorkedHours or 0):.2f}",
                (row.Notes or "").strip() or row.EntrySource,
            ]
        )
    if not rows:
        table_data.append(["No time entries for this period.", "", "", "", ""])
    table_data.append(["Total", "", "", f"{total_hours:.2f}", ""])

    timesheet_table = Table(
        table_data,
        colWidths=[1.15 * inch, 1.1 * inch, 1.75 * inch, 0.8 * inch, 2.15 * inch],
        repeatRows=1,
        hAlign="LEFT",
    )
    last_row_index = len(table_data) - 1
    no_entries = not rows
    table_style = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E7F8F5")),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#1F2933")),
        ("GRID", (0, 0), (-1, -1), 0.6, colors.HexColor("#D9CDBD")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (3, 1), (3, -1), "RIGHT"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("FONTNAME", (0, last_row_index), (0, last_row_index), "Helvetica-Bold"),
        ("FONTNAME", (3, last_row_index), (3, last_row_index), "Helvetica-Bold"),
        ("LINEABOVE", (0, last_row_index), (-1, last_row_index), 1, colors.HexColor("#1F2933")),
    ]
    if no_entries:
        table_style.extend(
            [
                ("SPAN", (0, 1), (4, 1)),
                ("FONTNAME", (0, 1), (0, 1), "Helvetica-Oblique"),
            ]
        )
    timesheet_table.setStyle(TableStyle(table_style))
    story.append(timesheet_table)

    doc.build(story)
    buffer.seek(0)
    return send_file(
        buffer,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=f"timesheet_{period_start.strftime('%m%d%Y')}.pdf",
    )


@app.route("/admin")
@login_required
@roles_required("Owner", "Executive Director", "Director", "Manager")
def admin_dashboard():
    viewer_id = current_employee_id()
    viewer_role = current_role_name()
    accessible_employees = fetch_accessible_employees(viewer_id, viewer_role)

    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        if viewer_role == "Owner":
            cursor.execute(
                """
                SELECT
                    LR.LeaveRequestId,
                    E.EmployeeId,
                    E.PayrollId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    LR.LeaveType,
                    LR.StartDate,
                    LR.EndDate,
                    LR.RequestedHours,
                    LR.ApprovalStatus
                FROM dbo.LeaveRequests LR
                INNER JOIN dbo.Employees E ON E.EmployeeId = LR.EmployeeId
                WHERE LR.ApprovalStatus = 'Pending'
                ORDER BY LR.RequestedAt ASC
                """
            )
        else:
            cursor.execute(
                """
                WITH EmployeeTree AS
                (
                    SELECT EmployeeId, UserId
                    FROM dbo.Employees
                    WHERE ReportsToUserId = ?
                      AND IsActive = 'Yes'

                    UNION ALL

                    SELECT E.EmployeeId, E.UserId
                    FROM dbo.Employees E
                    INNER JOIN EmployeeTree T ON E.ReportsToUserId = T.UserId
                    WHERE E.IsActive = 'Yes'
                )
                SELECT
                    LR.LeaveRequestId,
                    E.EmployeeId,
                    E.PayrollId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    LR.LeaveType,
                    LR.StartDate,
                    LR.EndDate,
                    LR.RequestedHours,
                    LR.ApprovalStatus
                FROM dbo.LeaveRequests LR
                INNER JOIN dbo.Employees E ON E.EmployeeId = LR.EmployeeId
                WHERE LR.ApprovalStatus = 'Pending'
                  AND E.EmployeeId IN (SELECT EmployeeId FROM EmployeeTree)
                ORDER BY LR.RequestedAt ASC
                """,
                current_user_id(),
            )
        pending_requests = cursor.fetchall()

    return render_template("admin.html", pending_requests=pending_requests, accessible_employees=accessible_employees)


@app.route("/owner/employees", methods=["GET", "POST"])
@login_required
@roles_required("Owner", "Executive Director")
def owner_employees():
    selected_employee_id = request.args.get("employee_id", type=int)
    viewer_id = current_employee_id()
    viewer_role = current_role_name()

    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        departments = fetch_departments()
        departments_by_id = {str(department.DepartmentId): department.DepartmentId for department in departments}
        departments_by_name = {department.DepartmentName.strip().lower(): department.DepartmentId for department in departments}

        if request.method == "POST":
            action = request.form.get("action", "create")
            first_name = request.form.get("first_name", "").strip()
            last_name = request.form.get("last_name", "").strip()
            email = request.form.get("email", "").strip().lower()
            user_id = request.form.get("user_id", "").strip().lower()
            role_name = request.form.get("role_name", "User")
            department_id_value = request.form.get("department_id", "").strip()
            personal_leave = 1 if request.form.get("personal_leave") == "1" else 0
            hire_date = request.form.get("hire_date")

            if action == "add_department":
                if viewer_role != "Owner":
                    flash("Only the Owner can add departments.", "error")
                    return redirect(url_for("owner_employees"))

                new_department_id = request.form.get("new_department_id", "").strip()
                new_department_name = request.form.get("new_department_name", "").strip()
                if not new_department_id or not new_department_name:
                    flash("Funding ID and funding source are required.", "error")
                    return redirect(url_for("owner_employees"))
                existing_department = departments_by_id.get(new_department_id)
                try:
                    create_department(cursor, int(new_department_id), new_department_name)
                    conn.commit()
                except ValueError:
                    conn.rollback()
                    flash("Funding ID must be a number.", "error")
                    return redirect(url_for("owner_employees"))
                except pyodbc.Error as exc:
                    conn.rollback()
                    flash(str(exc).strip() or "Could not add funding source.", "error")
                    return redirect(url_for("owner_employees"))

                if existing_department is not None:
                    flash("Funding source overwritten for that Funding ID.", "success")
                else:
                    flash("Funding source added.", "success")
                return redirect(url_for("owner_employees"))
            elif action == "repair_legacy_employees":
                if viewer_role != "Owner":
                    flash("Only the Owner can run employee repairs.", "error")
                    return redirect(url_for("owner_employees"))

                try:
                    repair_summary = repair_all_employee_identifiers(cursor)
                    conn.commit()
                except pyodbc.Error as exc:
                    conn.rollback()
                    flash(str(exc).strip() or "Could not repair employee records.", "error")
                    return redirect(url_for("owner_employees"))

                repaired_user_ids = repair_summary["repaired_user_ids"]
                repaired_reports_to = repair_summary["repaired_reports_to"]
                if repaired_user_ids or repaired_reports_to:
                    flash(
                        "Employee repair completed. "
                        f"Normalized {repaired_user_ids} user ID value(s) and repaired {repaired_reports_to} workflow link(s).",
                        "success",
                    )
                else:
                    flash("Employee repair completed. No legacy user IDs or workflow links needed changes.", "info")
                return redirect(url_for("owner_employees"))
            elif action == "create":
                if viewer_role != "Owner":
                    flash("Only the Owner can create employees.", "error")
                    return redirect(url_for("owner_employees"))

                if not first_name or not last_name:
                    flash("First name and last name are required.", "error")
                    return redirect(url_for("owner_employees"))

                if not email:
                    flash("Email is required.", "error")
                    return redirect(url_for("owner_employees"))
                if not department_id_value:
                    flash("Funding source is required.", "error")
                    return redirect(url_for("owner_employees"))
                try:
                    reports_to_user_id = resolve_supervisor_form_value(
                        cursor,
                        request.form.get("reports_to_employee_id", ""),
                        request.form.get("reports_to_user_id"),
                    )
                except ValueError as exc:
                    flash(str(exc), "error")
                    return redirect(url_for("owner_employees"))
                user_id = normalize_user_id_input(user_id, first_name, last_name, email)
                department_id = int(department_id_value)
                existing_employee = find_employee_duplicate(cursor, email, user_id)

                if existing_employee is not None:
                    flash(
                        "Duplicate employee found. "
                        f"{existing_employee.FirstName} {existing_employee.LastName} "
                        f"(Employee {existing_employee.EmployeeId}, Payroll {existing_employee.PayrollId}) "
                        "already uses that email or user ID.",
                        "error",
                    )
                    return redirect(url_for("owner_employees"))
                salt = os.urandom(8).hex().upper()
                password_hash = hash_password(salt, secrets.token_urlsafe(24))
                try:
                    cursor.execute(
                        """
                        EXEC dbo.usp_CreateEmployee
                            @FirstName = ?,
                            @LastName = ?,
                            @Email = ?,
                            @UserId = ?,
                            @RoleName = ?,
                            @DepartmentId = ?,
                            @PersonalLeave = ?,
                            @ReportsToUserId = ?,
                            @HireDate = ?,
                            @PasswordSalt = ?,
                            @PasswordHash = ?
                        """,
                        first_name,
                        last_name,
                        email,
                        user_id,
                        role_name,
                        department_id,
                        personal_leave,
                        reports_to_user_id,
                        hire_date,
                        salt,
                        password_hash,
                    )
                    created_row = cursor.fetchone()
                    setup_link = None
                    if created_row is not None:
                        setup_link = create_password_setup_link(conn, getattr(created_row, "EmployeeId", 0), "Setup")
                    conn.commit()
                except pyodbc.Error as exc:
                    conn.rollback()
                    duplicate_employee = find_employee_duplicate(cursor, email, user_id)
                    if duplicate_employee is not None:
                        flash(
                            "Duplicate employee found. "
                            f"{duplicate_employee.FirstName} {duplicate_employee.LastName} "
                            f"(Employee {duplicate_employee.EmployeeId}, Payroll {duplicate_employee.PayrollId}) "
                            "already uses that email or user ID.",
                            "error",
                        )
                        return redirect(url_for("owner_employees"))
                    flash(str(exc).strip() or "Could not create employee.", "error")
                    return redirect(url_for("owner_employees"))

                if created_row is not None:
                    session["generated_setup_links"] = [
                        {
                            "payroll_id": getattr(created_row, "PayrollId", ""),
                            "employee_id": getattr(created_row, "EmployeeId", ""),
                            "full_name": f"{first_name} {last_name}".strip(),
                            "email": email,
                            "setup_link": setup_link or "",
                        }
                    ]
                flash("Employee created. A one-time password setup link was generated for first login.", "success")
                return redirect(url_for("owner_employees"))
            elif action == "import_csv":
                if viewer_role != "Owner":
                    flash("Only the Owner can import employees.", "error")
                    return redirect(url_for("owner_employees"))

                uploaded_file = request.files.get("csv_file")
                if not uploaded_file or not uploaded_file.filename:
                    flash("Choose a CSV file to import.", "error")
                    return redirect(url_for("owner_employees"))

                try:
                    import_rows = parse_employee_import_csv(uploaded_file)
                except ValueError as exc:
                    flash(str(exc), "error")
                    return redirect(url_for("owner_employees"))

                supervisor_user_ids_by_payroll_id, supervisor_user_ids_by_user_id = fetch_supervisor_lookup(cursor)
                employees_by_payroll_id, employees_by_email, employees_by_user_id = fetch_employee_import_lookup(cursor)
                imported_count = 0
                updated_count = 0
                duplicate_notice_count = 0
                error_messages = []
                generated_setup_links = []
                payroll_id_mappings = []

                for row in import_rows:
                    try:
                        first_name = row["first_name"]
                        last_name = row["last_name"]
                        if not first_name or not last_name:
                            raise ValueError("First name and last name are required.")

                        role_name = row["role_name"] or "User"
                        temporary_secret = secrets.token_urlsafe(24)

                        email = row["email"]
                        if not email:
                            raise ValueError("Email is required.")
                        email = email.lower()
                        user_id = normalize_user_id_input(row["user_id"], first_name, last_name, email)
                        if not user_id:
                            raise ValueError("User ID could not be generated. Provide a user_id in the CSV.")
                        department_id = resolve_department_id(row, departments_by_id, departments_by_name)
                        normalized_hire_date = normalize_import_hire_date(row["hire_date"])

                        reports_to_user_id = resolve_supervisor_user_id(
                            row,
                            supervisor_user_ids_by_payroll_id,
                            supervisor_user_ids_by_user_id,
                        )
                        matched_employee = None
                        payroll_id_value = row["payroll_id"].strip()
                        matched_by_payroll = None
                        matched_by_email = employees_by_email.get(email)
                        matched_by_user_id = employees_by_user_id.get(user_id)

                        if payroll_id_value:
                            matched_by_payroll = employees_by_payroll_id.get(payroll_id_value)
                            if matched_by_payroll is not None:
                                matched_employee = matched_by_payroll

                        for candidate in (matched_by_email, matched_by_user_id):
                            if candidate is None:
                                continue
                            if matched_employee is None:
                                matched_employee = candidate
                            elif matched_employee.PayrollId != candidate.PayrollId:
                                raise ValueError(
                                    "Payroll ID, email, and user ID point to different employees."
                                )

                        if not normalized_hire_date:
                            if matched_employee is not None and getattr(matched_employee, "HireDate", None):
                                normalized_hire_date = matched_employee.HireDate.isoformat()
                            else:
                                normalized_hire_date = date.today().isoformat()

                        salt = os.urandom(8).hex().upper()
                        password_hash = hash_password(salt, temporary_secret)
                        personal_leave_value = parse_csv_bool(row["personal_leave"])

                        if matched_employee is None:
                            cursor.execute(
                                """
                                EXEC dbo.usp_CreateEmployee
                                    @FirstName = ?,
                                    @LastName = ?,
                                    @Email = ?,
                                    @UserId = ?,
                                    @RoleName = ?,
                                    @DepartmentId = ?,
                                    @PersonalLeave = ?,
                                    @ReportsToUserId = ?,
                                    @HireDate = ?,
                                    @PasswordSalt = ?,
                                    @PasswordHash = ?
                                """,
                                first_name,
                                last_name,
                                email,
                                user_id,
                                role_name,
                                department_id,
                                personal_leave_value,
                                reports_to_user_id,
                                normalized_hire_date,
                                salt,
                                password_hash,
                            )
                            conn.commit()
                            imported_count += 1
                            employees_by_payroll_id, employees_by_email, employees_by_user_id = fetch_employee_import_lookup(cursor)
                            matched_employee = employees_by_email.get(email) or employees_by_user_id.get(user_id)
                            if matched_employee is not None and payroll_id_value and matched_employee.PayrollId != payroll_id_value:
                                overwrite_employee_payroll_id(cursor, matched_employee.EmployeeId, payroll_id_value)
                                matched_employee = fetch_employee_by_id(cursor, matched_employee.EmployeeId)
                            if matched_employee and row["is_active"]:
                                matched_employee = canonicalize_existing_employee_identifiers(cursor, matched_employee.EmployeeId)
                                if matched_employee is not None and (matched_employee.UserId or "").strip() != user_id:
                                    reassign_employee_reports(cursor, matched_employee.UserId, user_id)
                                cursor.execute(
                                    """
                                    EXEC dbo.usp_UpdateEmployee
                                        @EmployeeId = ?,
                                        @FirstName = ?,
                                        @LastName = ?,
                                        @Email = ?,
                                        @UserId = ?,
                                        @RoleName = ?,
                                        @DepartmentId = ?,
                                        @PersonalLeave = ?,
                                        @ReportsToUserId = ?,
                                        @HireDate = ?,
                                        @IsActive = ?
                                    """,
                                    matched_employee.EmployeeId,
                                    first_name,
                                    last_name,
                                    email,
                                    user_id,
                                    role_name,
                                    department_id,
                                    personal_leave_value,
                                    reports_to_user_id,
                                    normalized_hire_date,
                                    parse_csv_yes_no(row["is_active"], "IsActive"),
                                )
                        else:
                            matched_employee = canonicalize_existing_employee_identifiers(cursor, matched_employee.EmployeeId)
                            if matched_employee is not None and payroll_id_value and matched_employee.PayrollId != payroll_id_value:
                                overwrite_employee_payroll_id(cursor, matched_employee.EmployeeId, payroll_id_value)
                                matched_employee = fetch_employee_by_id(cursor, matched_employee.EmployeeId)
                            is_active_value = (
                                parse_csv_yes_no(row["is_active"], "IsActive")
                                if row["is_active"]
                                else matched_employee.IsActive
                            )
                            if matched_employee is not None and (matched_employee.UserId or "").strip() != user_id:
                                reassign_employee_reports(cursor, matched_employee.UserId, user_id)
                            cursor.execute(
                                """
                                EXEC dbo.usp_UpdateEmployee
                                    @EmployeeId = ?,
                                    @FirstName = ?,
                                    @LastName = ?,
                                    @Email = ?,
                                    @UserId = ?,
                                    @RoleName = ?,
                                    @DepartmentId = ?,
                                    @PersonalLeave = ?,
                                    @ReportsToUserId = ?,
                                    @HireDate = ?,
                                    @IsActive = ?
                                """,
                                matched_employee.EmployeeId,
                                first_name,
                                last_name,
                                email,
                                user_id,
                                role_name,
                                department_id,
                                personal_leave_value,
                                reports_to_user_id,
                                normalized_hire_date,
                                is_active_value,
                            )
                            updated_count += 1

                        if matched_employee is not None:
                            duplicate_notice_count += 1
                            cursor.execute(
                                """
                                EXEC dbo.usp_ResetEmployeePassword
                                    @EmployeeId = ?,
                                    @PasswordSalt = ?,
                                    @PasswordHash = ?
                                """,
                                matched_employee.EmployeeId,
                                salt,
                                password_hash,
                            )
                            setup_link = create_password_setup_link(conn, matched_employee.EmployeeId, "Setup")
                        conn.commit()
                        employees_by_payroll_id, employees_by_email, employees_by_user_id = fetch_employee_import_lookup(cursor)
                        if matched_employee is not None:
                            generated_setup_links.append(
                                {
                                    "line_number": row["line_number"],
                                    "employee_id": matched_employee.EmployeeId,
                                    "payroll_id": matched_employee.PayrollId,
                                    "full_name": f"{first_name} {last_name}".strip(),
                                    "email": email,
                                    "setup_link": setup_link,
                                }
                            )
                        if matched_employee is not None:
                            payroll_id_mappings.append(
                                {
                                    "line_number": row["line_number"],
                                    "employee_id": matched_employee.EmployeeId,
                                    "csv_payroll_id": payroll_id_value,
                                    "database_payroll_id": matched_employee.PayrollId,
                                    "full_name": f"{first_name} {last_name}".strip(),
                                    "email": email,
                                    "user_id": user_id,
                                    "result": "Created" if matched_by_payroll is None and matched_by_email is None and matched_by_user_id is None else "Updated",
                                }
                            )
                    except (ValueError, pyodbc.Error) as exc:
                        conn.rollback()
                        db_message = str(exc).strip() or "Import failed."
                        error_messages.append(f"Line {row['line_number']}: {db_message}")

                if imported_count:
                    flash(f"Imported {imported_count} employee(s) from CSV.", "success")
                if updated_count:
                    flash(f"Updated {updated_count} existing employee(s) from CSV.", "success")
                if duplicate_notice_count:
                    flash(
                        f"{duplicate_notice_count} duplicate employee row(s) matched an existing employee by payroll ID, email, or user ID and were updated instead of added.",
                        "info",
                    )
                if generated_setup_links:
                    session["generated_setup_links"] = generated_setup_links
                    flash(
                        f"Generated one-time password setup links for {len(generated_setup_links)} employee(s). Save them now because they are only shown once.",
                        "info",
                    )
                if payroll_id_mappings:
                    session["import_payroll_id_mappings"] = payroll_id_mappings
                    flash(
                        f"Prepared a payroll ID mapping file for {len(payroll_id_mappings)} imported row(s).",
                        "info",
                    )

                if error_messages:
                    preview = " | ".join(error_messages[:8])
                    if len(error_messages) > 8:
                        preview += f" | ...and {len(error_messages) - 8} more"
                    flash(f"{len(error_messages)} row(s) could not be imported. {preview}", "error")

                if not imported_count and not error_messages:
                    flash("No employee rows were imported.", "error")
                return redirect(url_for("owner_employees"))
            elif action == "reset_password":
                employee_id = int(request.form["employee_id"])
                if viewer_role == "Executive Director" and not can_access_employee(employee_id, viewer_id, viewer_role):
                    flash("You do not have access to that employee.", "error")
                    return redirect(url_for("owner_employees"))

                temporary_secret = secrets.token_urlsafe(24)
                salt = os.urandom(8).hex().upper()
                password_hash = hash_password(salt, temporary_secret)
                cursor.execute(
                    """
                    EXEC dbo.usp_ResetEmployeePassword
                        @EmployeeId = ?,
                        @PasswordSalt = ?,
                        @PasswordHash = ?
                    """,
                    employee_id,
                    salt,
                    password_hash,
                )
                setup_link = create_password_setup_link(conn, employee_id, "Reset")
                conn.commit()
                session["generated_setup_links"] = [
                    {
                        "employee_id": employee_id,
                        "payroll_id": request.form.get("payroll_id", ""),
                        "full_name": request.form.get("employee_name", "").strip(),
                        "email": request.form.get("employee_email", "").strip(),
                        "setup_link": setup_link,
                    }
                ]
                flash("Password reset. A one-time password setup link was generated for the employee.", "success")
                return redirect(url_for("owner_employees", employee_id=employee_id))
            elif action == "make_inactive":
                if viewer_role != "Owner":
                    flash("Only the Owner can make employees inactive.", "error")
                    return redirect(url_for("owner_employees"))

                employee_id = int(request.form["employee_id"])
                employee = fetch_employee_by_id(cursor, employee_id)
                if employee is None:
                    flash("Employee not found.", "error")
                    return redirect(url_for("owner_employees"))
                if employee.EmployeeId == viewer_id:
                    flash("You cannot make your own account inactive while signed in.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                if is_seeded_owner_account(employee):
                    flash("The seeded owner account must stay active.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))

                try:
                    changed = make_employee_inactive(cursor, employee_id)
                    conn.commit()
                except pyodbc.Error as exc:
                    conn.rollback()
                    flash(str(exc).strip() or "Could not update employee status.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))

                if changed:
                    flash("Employee marked inactive. Their history was preserved.", "success")
                else:
                    flash("Employee was already inactive.", "info")
                return redirect(url_for("owner_employees", employee_id=employee_id))
            elif action == "delete_employee":
                if viewer_role != "Owner":
                    flash("Only the Owner can delete employees.", "error")
                    return redirect(url_for("owner_employees"))

                employee_id = int(request.form["employee_id"])
                employee = fetch_employee_by_id(cursor, employee_id)
                if employee is None:
                    flash("Employee not found.", "error")
                    return redirect(url_for("owner_employees"))
                if employee.EmployeeId == viewer_id:
                    flash("You cannot delete the account you are currently using.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                if is_seeded_owner_account(employee):
                    flash("The seeded owner account cannot be deleted.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))

                try:
                    deleted_employee = delete_employee_records(conn, cursor, employee_id)
                    conn.commit()
                except (ValueError, pyodbc.Error) as exc:
                    conn.rollback()
                    flash(
                        str(exc).strip()
                        or "Could not delete employee. Make the employee inactive instead if you need to preserve history.",
                        "error",
                    )
                    return redirect(url_for("owner_employees", employee_id=employee_id))

                flash(
                    f"Deleted employee {deleted_employee.FirstName} {deleted_employee.LastName}. "
                    "If you only wanted to block access, use Make Inactive next time so the record stays in the system.",
                    "success",
                )
                return redirect(url_for("owner_employees"))
            else:
                employee_id = int(request.form["employee_id"])
                if viewer_role == "Executive Director" and not can_access_employee(employee_id, viewer_id, viewer_role):
                    flash("You do not have access to that employee.", "error")
                    return redirect(url_for("owner_employees"))

                if not first_name or not last_name:
                    flash("First name and last name are required.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))

                if not email:
                    flash("Email is required.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                if not department_id_value:
                    flash("Funding source is required.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                try:
                    reports_to_user_id = resolve_supervisor_form_value(
                        cursor,
                        request.form.get("reports_to_employee_id", ""),
                        request.form.get("reports_to_user_id"),
                    )
                except ValueError as exc:
                    flash(str(exc), "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                user_id = normalize_user_id_input(user_id, first_name, last_name, email)
                department_id = int(department_id_value)
                is_active = "Yes" if request.form.get("is_active") == "1" else "No"
                current_employee = canonicalize_existing_employee_identifiers(cursor, employee_id)
                if current_employee is None:
                    flash("Employee not found.", "error")
                    return redirect(url_for("owner_employees"))
                existing_employee = find_employee_duplicate(cursor, email, user_id, exclude_employee_id=employee_id)
                if existing_employee is not None:
                    flash(
                        "Duplicate employee found. "
                        f"{existing_employee.FirstName} {existing_employee.LastName} "
                        f"(Employee {existing_employee.EmployeeId}, Payroll {existing_employee.PayrollId}) "
                        "already uses that email or user ID.",
                        "error",
                    )
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                try:
                    if (current_employee.UserId or "").strip() != user_id:
                        reassign_employee_reports(cursor, current_employee.UserId, user_id)
                    cursor.execute(
                        """
                        EXEC dbo.usp_UpdateEmployee
                            @EmployeeId = ?,
                            @FirstName = ?,
                            @LastName = ?,
                            @Email = ?,
                            @UserId = ?,
                            @RoleName = ?,
                            @DepartmentId = ?,
                            @PersonalLeave = ?,
                            @ReportsToUserId = ?,
                            @HireDate = ?,
                            @IsActive = ?
                        """,
                        employee_id,
                        first_name,
                        last_name,
                        email,
                        user_id,
                        role_name,
                        department_id,
                        personal_leave,
                        reports_to_user_id,
                        hire_date,
                        is_active,
                    )
                    conn.commit()
                except pyodbc.Error as exc:
                    conn.rollback()
                    duplicate_employee = find_employee_duplicate(cursor, email, user_id, exclude_employee_id=employee_id)
                    if duplicate_employee is not None:
                        flash(
                            "Duplicate employee found. "
                            f"{duplicate_employee.FirstName} {duplicate_employee.LastName} "
                            f"(Employee {duplicate_employee.EmployeeId}, Payroll {duplicate_employee.PayrollId}) "
                            "already uses that email or user ID.",
                            "error",
                        )
                        return redirect(url_for("owner_employees", employee_id=employee_id))
                    flash(str(exc).strip() or "Could not update employee.", "error")
                    return redirect(url_for("owner_employees", employee_id=employee_id))
                flash("Employee updated.", "success")
                return redirect(url_for("owner_employees", employee_id=employee_id))

        cursor.execute("SELECT RoleName FROM dbo.Roles ORDER BY RoleName")
        roles = cursor.fetchall()
        supervisors = get_supervisor_choices()

        if viewer_role == "Owner":
            cursor.execute(
                """
                SELECT
                    E.EmployeeId,
                    E.PayrollId,
                    E.DepartmentId,
                    D.DepartmentName,
                    E.FirstName,
                    E.LastName,
                    E.Email,
                    E.UserId,
                    E.PersonalLeave AS IsHeadStart,
                    E.ReportsToUserId,
                    E.HireDate,
                    R.RoleName,
                    E.IsActive
                FROM dbo.Employees E
                INNER JOIN dbo.Departments D ON D.DepartmentId = E.DepartmentId
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                ORDER BY E.LastName, E.FirstName
                """
            )
        else:
            cursor.execute(
                """
                WITH EmployeeTree AS
                (
                    SELECT EmployeeId, UserId
                    FROM dbo.Employees
                    WHERE ReportsToUserId = ?
                      AND IsActive = 'Yes'

                    UNION ALL

                    SELECT E.EmployeeId, E.UserId
                    FROM dbo.Employees E
                    INNER JOIN EmployeeTree T ON E.ReportsToUserId = T.UserId
                    WHERE E.IsActive = 'Yes'
                )
                SELECT
                    E.EmployeeId,
                    E.PayrollId,
                    E.DepartmentId,
                    D.DepartmentName,
                    E.FirstName,
                    E.LastName,
                    E.Email,
                    E.UserId,
                    E.PersonalLeave AS IsHeadStart,
                    E.ReportsToUserId,
                    E.HireDate,
                    R.RoleName,
                    E.IsActive
                FROM dbo.Employees E
                INNER JOIN dbo.Departments D ON D.DepartmentId = E.DepartmentId
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                WHERE E.EmployeeId IN (SELECT EmployeeId FROM EmployeeTree)
                ORDER BY E.LastName, E.FirstName
                """,
                current_user_id(),
            )
        employees = cursor.fetchall()

    selected_employee = None
    generated_import_passwords = session.pop("generated_import_passwords", None)
    import_payroll_id_mappings = session.get("import_payroll_id_mappings")
    if employees:
        if selected_employee_id is None:
            selected_employee = employees[0]
        else:
            selected_employee = next(
                (employee for employee in employees if employee.EmployeeId == selected_employee_id),
                employees[0],
            )

    return render_template(
        "owner_employees.html",
        roles=roles,
        departments=departments,
        supervisors=supervisors,
        employees=employees,
        selected_employee=selected_employee,
        generated_import_passwords=generated_import_passwords,
        import_payroll_id_mappings=import_payroll_id_mappings,
    )


@app.route("/owner/employees/export")
@login_required
@roles_required("Owner")
def export_employees():
    export_format = (request.args.get("format") or "csv").strip().lower()
    if export_format not in {"csv", "txt"}:
        flash("Unsupported employee export format.", "error")
        return redirect(url_for("owner_employees"))

    employees = fetch_employee_export_rows()
    today_stamp = datetime.now().strftime("%Y%m%d")

    if export_format == "csv":
        csv_buffer = StringIO()
        writer = csv.writer(csv_buffer)
        writer.writerow(
            [
                "Employee Id",
                "FirstName",
                "LastName",
                "Email",
                "User Id",
                "Payroll Id",
                "Funding Id",
                "Funding Source",
                "RoleName",
                "PersonalLeave",
                "Workflow",
                "HireDate",
                "IsActive",
            ]
        )
        for employee in employees:
            writer.writerow(
                [
                    employee.EmployeeId,
                    employee.FirstName,
                    employee.LastName,
                    employee.Email,
                    employee.UserId,
                    employee.PayrollId,
                    employee.DepartmentId,
                    employee.DepartmentName,
                    employee.RoleName,
                    "Yes" if employee.PersonalLeave else "No",
                    employee.ReportsToUserId or "",
                    employee.HireDate.isoformat() if employee.HireDate else "",
                    employee.IsActive,
                ]
            )

        buffer = BytesIO(csv_buffer.getvalue().encode("utf-8"))
        buffer.seek(0)
        return send_file(
            buffer,
            mimetype="text/csv",
            as_attachment=True,
            download_name=f"employees_{today_stamp}.csv",
        )

    lines = [
        "Employee Export",
        f"Generated: {datetime.now().strftime('%m/%d/%Y %I:%M %p')}",
        "",
    ]
    for employee in employees:
        lines.extend(
            [
                f"Employee Id: {employee.EmployeeId}",
                f"FirstName: {employee.FirstName}",
                f"LastName: {employee.LastName}",
                f"Email: {employee.Email}",
                f"User Id: {employee.UserId}",
                f"Payroll Id: {employee.PayrollId}",
                f"Funding Id: {employee.DepartmentId}",
                f"Funding Source: {employee.DepartmentName}",
                f"RoleName: {employee.RoleName}",
                f"PersonalLeave: {'Yes' if employee.PersonalLeave else 'No'}",
                f"Workflow: {employee.ReportsToUserId or ''}",
                f"Hire Date: {employee.HireDate.isoformat() if employee.HireDate else ''}",
                f"IsActive: {employee.IsActive}",
                "",
            ]
        )

    buffer = BytesIO("\n".join(lines).encode("utf-8"))
    buffer.seek(0)
    return send_file(
        buffer,
        mimetype="text/plain",
        as_attachment=True,
        download_name=f"employees_{today_stamp}.txt",
    )


@app.route("/owner/employees/import-payroll-mapping")
@login_required
@roles_required("Owner")
def download_import_payroll_mapping():
    mappings = session.get("import_payroll_id_mappings")
    if not mappings:
        flash("No import payroll ID mapping is available yet.", "error")
        return redirect(url_for("owner_employees"))

    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    writer.writerow(
        [
            "LineNumber",
            "EmployeeId",
            "CsvPayrollId",
            "DatabasePayrollId",
            "FullName",
            "Email",
            "UserId",
            "Result",
        ]
    )
    for item in mappings:
        writer.writerow(
            [
                item["line_number"],
                item["employee_id"],
                item["csv_payroll_id"],
                item["database_payroll_id"],
                item["full_name"],
                item["email"],
                item["user_id"],
                item["result"],
            ]
        )

    today_stamp = date.today().strftime("%Y%m%d")
    buffer = BytesIO(csv_buffer.getvalue().encode("utf-8"))
    buffer.seek(0)
    return send_file(
        buffer,
        mimetype="text/csv",
        as_attachment=True,
        download_name=f"employee_import_payroll_mapping_{today_stamp}.csv",
    )


@app.route("/leave/manual", methods=["GET", "POST"])
@login_required
@roles_required("Owner", "Leave Manager")
def manual_leave_entry():
    viewer_name = session["user"]["full_name"]
    employees = fetch_manual_leave_employees()
    selected_employee_id = request.args.get("employee_id", type=int)

    if request.method == "POST":
        selected_employee_id = request.form.get("employee_id", type=int)

    selected_employee = None
    if employees:
        if selected_employee_id is None:
            selected_employee = employees[0]
        else:
            selected_employee = next(
                (employee for employee in employees if employee.EmployeeId == selected_employee_id),
                employees[0],
            )

    if not selected_employee:
        flash("No active employees are available for manual leave entry.", "error")
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        leave_type = request.form.get("leave_type", "")
        hours = request.form.get("hours", type=float)
        notes = request.form.get("notes", "").strip()

        if leave_type not in {"Annual", "Sick", "Personal"}:
            flash("Select a valid leave type.", "error")
            return render_template(
                "manual_leave_entry.html",
                employees=employees,
                selected_employee=selected_employee,
            )

        if hours is None or hours == 0:
            flash("Enter non-zero leave hours.", "error")
            return render_template(
                "manual_leave_entry.html",
                employees=employees,
                selected_employee=selected_employee,
            )

        if selected_employee.IsHeadStart and leave_type == "Annual":
            flash("Head Start employees use Personal leave instead of Annual leave.", "error")
            return render_template(
                "manual_leave_entry.html",
                employees=employees,
                selected_employee=selected_employee,
            )

        if not selected_employee.IsHeadStart and leave_type == "Personal":
            flash("Only Head Start employees can receive Personal leave adjustments.", "error")
            return render_template(
                "manual_leave_entry.html",
                employees=employees,
                selected_employee=selected_employee,
            )

        audit_note = f"Manual leave entry by {viewer_name}"
        if notes:
            audit_note = f"{audit_note}: {notes}"

        with get_connection() as conn:
            ensure_role_catalog(conn)
            cursor = conn.cursor()
            cursor.execute(
                """
                INSERT INTO dbo.LeaveLedger
                (
                    EmployeeId,
                    EntryDate,
                    LeaveType,
                    Hours,
                    EntryReason,
                    Notes
                )
                VALUES
                (
                    ?, ?, ?, ?, 'Adjustment', ?
                )
                """,
                selected_employee.EmployeeId,
                date.today(),
                leave_type,
                hours,
                audit_note,
            )
            conn.commit()

        flash("Manual leave hours posted.", "success")
        return redirect(url_for("manual_leave_entry", employee_id=selected_employee.EmployeeId))

    return render_template(
        "manual_leave_entry.html",
        employees=employees,
        selected_employee=selected_employee,
    )


@app.route("/admin/leave/<int:leave_request_id>", methods=["POST"])
@login_required
@roles_required("Owner", "Executive Director", "Director", "Manager")
def process_leave_request(leave_request_id: int):
    action = request.form["action"]
    approval_status = "Approved" if action == "approve" else "Denied"
    viewer_id = current_employee_id()
    viewer_role = current_role_name()

    with get_connection() as conn:
        ensure_role_catalog(conn)
        cursor = conn.cursor()
        if viewer_role != "Owner":
            cursor.execute(
                """
                WITH RECURSIVE EmployeeTree AS
                (
                    SELECT EmployeeId, UserId
                    FROM dbo.Employees
                    WHERE ReportsToUserId = ?
                      AND IsActive = 'Yes'

                    UNION ALL

                    SELECT E.EmployeeId, E.UserId
                    FROM dbo.Employees E
                    INNER JOIN EmployeeTree T ON E.ReportsToUserId = T.UserId
                    WHERE E.IsActive = 'Yes'
                )
                SELECT 1
                FROM dbo.LeaveRequests LR
                WHERE LeaveRequestId = ?
                  AND LR.EmployeeId IN (SELECT EmployeeId FROM EmployeeTree)
                """,
                current_user_id(),
                leave_request_id,
            )
            if not cursor.fetchone():
                flash("You do not have access to that leave request.", "error")
                return redirect(url_for("admin_dashboard"))

        cursor.execute(
            """
            EXEC dbo.usp_ProcessLeaveRequest
                @LeaveRequestId = ?,
                @ApprovalStatus = ?,
                @ApprovedByEmployeeId = ?
            """,
            leave_request_id,
            approval_status,
            session["user"]["employee_id"],
        )
        conn.commit()

    flash(f"Leave request {approval_status.lower()}.", "success")
    return redirect(url_for("admin_dashboard"))


@app.route("/board")
@login_required
@roles_required("Owner", "Executive Director", "Director", "Manager")
def live_board():
    viewer_id = current_employee_id()
    viewer_role = current_role_name()

    with get_connection() as conn:
        ensure_timesheet_admin_schema(conn)
        cursor = conn.cursor()
        if viewer_role == "Owner":
            cursor.execute(
                """
                WITH LatestEntry AS
                (
                    SELECT
                        T.EmployeeId,
                        T.TimeEntryId,
                        T.ClockInTime,
                        T.ClockOutTime,
                        ROW_NUMBER() OVER (PARTITION BY T.EmployeeId ORDER BY IFNULL(T.ClockOutTime, T.ClockInTime) DESC, T.TimeEntryId DESC) AS RowNum
                    FROM dbo.TimeEntries T
                )
                SELECT
                    E.EmployeeId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    R.RoleName,
                    L.TimeEntryId,
                    L.ClockInTime,
                    L.ClockOutTime
                FROM dbo.Employees E
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                LEFT JOIN LatestEntry L ON L.EmployeeId = E.EmployeeId AND L.RowNum = 1
                WHERE E.IsActive = 'Yes'
                ORDER BY E.LastName, E.FirstName
                """
            )
        else:
            cursor.execute(
                """
                WITH RECURSIVE EmployeeTree AS
                (
                    SELECT EmployeeId, UserId
                    FROM dbo.Employees
                    WHERE ReportsToUserId = ?
                      AND IsActive = 'Yes'

                    UNION ALL

                    SELECT E.EmployeeId, E.UserId
                    FROM dbo.Employees E
                    INNER JOIN EmployeeTree T ON E.ReportsToUserId = T.UserId
                    WHERE E.IsActive = 'Yes'
                ),
                LatestEntry AS
                (
                    SELECT
                        T.EmployeeId,
                        T.TimeEntryId,
                        T.ClockInTime,
                        T.ClockOutTime,
                        ROW_NUMBER() OVER (PARTITION BY T.EmployeeId ORDER BY IFNULL(T.ClockOutTime, T.ClockInTime) DESC, T.TimeEntryId DESC) AS RowNum
                    FROM dbo.TimeEntries T
                )
                SELECT
                    E.EmployeeId,
                    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
                    R.RoleName,
                    L.TimeEntryId,
                    L.ClockInTime,
                    L.ClockOutTime
                FROM dbo.Employees E
                INNER JOIN dbo.Roles R ON R.RoleId = E.RoleId
                LEFT JOIN LatestEntry L ON L.EmployeeId = E.EmployeeId AND L.RowNum = 1
                WHERE E.EmployeeId IN (SELECT EmployeeId FROM EmployeeTree)
                ORDER BY E.LastName, E.FirstName
                """,
                current_user_id(),
            )
        board_rows = cursor.fetchall()

    return render_template(
        "board.html",
        board_rows=board_rows,
        can_edit_times=viewer_role in TIME_EDIT_ROLES,
        can_manage_clocking=viewer_role in CLOCK_MANAGEMENT_ROLES,
    )


@app.route("/employee/<int:employee_id>/clock", methods=["POST"])
@login_required
def manage_employee_clock(employee_id: int):
    viewer_id = current_employee_id()
    viewer_role = current_role_name()
    action = request.form.get("action")

    if action not in {"clock_in", "clock_out"}:
        flash("Invalid clock action.", "error")
        return redirect(url_for("live_board"))

    if not can_manage_clock_for_target(employee_id, viewer_id, viewer_role):
        flash("You do not have permission to clock that employee in or out.", "error")
        return redirect(url_for("live_board"))

    with get_connection() as conn:
        cursor = conn.cursor()
        if action == "clock_in":
            cursor.execute("EXEC dbo.usp_ClockIn @EmployeeId = ?", employee_id)
            success_message = "Clock-in recorded."
        else:
            cursor.execute("EXEC dbo.usp_ClockOut @EmployeeId = ?", employee_id)
            success_message = "Clock-out recorded."
        conn.commit()

    flash(success_message, "success")
    return redirect(url_for("live_board"))


@app.route("/timesheets/review")
@login_required
@roles_required("Owner", "Director", "Executive Director", "Manager")
def review_timesheets():
    viewer_id = current_employee_id()
    viewer_role = current_role_name()
    accessible_employees = fetch_accessible_employees(viewer_id, viewer_role)
    return render_template("review_timesheets.html", accessible_employees=accessible_employees)


@app.route("/employee/<int:employee_id>/time-entry/new", methods=["GET", "POST"])
@login_required
@roles_required("Owner", "Executive Director", "Director", "Manager")
def create_manual_time_entry(employee_id: int):
    viewer_id = current_employee_id()
    viewer_role = current_role_name()

    if not can_access_employee(employee_id, viewer_id, viewer_role):
        flash("You do not have access to that employee timesheet.", "error")
        return redirect(url_for("review_timesheets"))

    with get_connection() as conn:
        ensure_timesheet_admin_schema(conn)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT EmployeeId,
                   LTRIM(RTRIM(CONCAT(FirstName, ' ', LastName))) AS FullName
            FROM dbo.Employees
            WHERE EmployeeId = ?
            """,
            employee_id,
        )
        employee = cursor.fetchone()
        if not employee:
            flash("Employee not found.", "error")
            return redirect(url_for("review_timesheets"))

        if request.method == "POST":
            notes = request.form.get("notes", "").strip() or None
            change_reason = request.form.get("change_reason", "").strip()

            if not change_reason:
                flash("Please include a reason for the manual entry.", "error")
                return render_template("manual_time_entry.html", employee=employee)

            try:
                clock_in_time = parse_local_datetime(request.form.get("clock_in_time", ""), "Clock in")
                clock_out_raw = request.form.get("clock_out_time", "").strip()
                clock_out_time = parse_local_datetime(clock_out_raw, "Clock out") if clock_out_raw else None
            except ValueError as exc:
                flash(str(exc), "error")
                return render_template("manual_time_entry.html", employee=employee)

            if clock_out_time and clock_out_time < clock_in_time:
                flash("Clock out must be later than clock in.", "error")
                return render_template("manual_time_entry.html", employee=employee)

            cursor.execute(
                """
                INSERT INTO dbo.TimeEntries
                (
                    EmployeeId,
                    ClockInTime,
                    ClockOutTime,
                    Notes,
                    EntrySource,
                    CreatedByEmployeeId,
                    LastModifiedAt,
                    LastModifiedByEmployeeId
                )
                VALUES
                (
                    ?, ?, ?, ?, 'Manual', ?, UTC_TIMESTAMP(6), ?
                )
                """,
                employee.EmployeeId,
                clock_in_time,
                clock_out_time,
                notes,
                viewer_id,
                viewer_id,
            )
            new_entry_id = cursor.lastrowid
            write_time_entry_audit(
                cursor,
                time_entry_id=new_entry_id,
                employee_id=employee.EmployeeId,
                action_type="ManualCreate",
                changed_by_employee_id=viewer_id,
                change_reason=change_reason,
                old_clock_in_time=None,
                new_clock_in_time=clock_in_time,
                old_clock_out_time=None,
                new_clock_out_time=clock_out_time,
                old_notes=None,
                new_notes=notes,
                old_entry_source=None,
                new_entry_source="Manual",
            )
            conn.commit()
            flash("Manual time entry added.", "success")
            return redirect(url_for("timesheet", employee_id=employee.EmployeeId))

    return render_template("manual_time_entry.html", employee=employee)


@app.route("/time-entry/<int:time_entry_id>/edit", methods=["GET", "POST"])
@login_required
@roles_required("Owner", "Executive Director", "Director", "Manager")
def edit_time_entry(time_entry_id: int):
    viewer_id = current_employee_id()
    viewer_role = current_role_name()

    with get_connection() as conn:
        ensure_timesheet_admin_schema(conn)
        cursor = conn.cursor()
        entry = fetch_time_entry_with_employee(cursor, time_entry_id)
        if not entry:
            flash("Time entry not found.", "error")
            return redirect(url_for("live_board"))
        if not can_access_employee(entry.EmployeeId, viewer_id, viewer_role):
            flash("You do not have access to that employee time entry.", "error")
            return redirect(url_for("live_board"))

        if request.method == "POST":
            change_reason = request.form.get("change_reason", "").strip()
            notes = request.form.get("notes", "").strip() or None

            if not change_reason:
                flash("Please include a reason for the edit.", "error")
                audit_rows = fetch_time_entry_audit(cursor, time_entry_id)
                return render_template("edit_time_entry.html", entry=entry, audit_rows=audit_rows)

            try:
                updated_clock_in = parse_local_datetime(request.form.get("clock_in_time", ""), "Clock in")
                clock_out_raw = request.form.get("clock_out_time", "").strip()
                updated_clock_out = parse_local_datetime(clock_out_raw, "Clock out") if clock_out_raw else None
            except ValueError as exc:
                flash(str(exc), "error")
                audit_rows = fetch_time_entry_audit(cursor, time_entry_id)
                return render_template("edit_time_entry.html", entry=entry, audit_rows=audit_rows)

            if updated_clock_out and updated_clock_out < updated_clock_in:
                flash("Clock out must be later than clock in.", "error")
                audit_rows = fetch_time_entry_audit(cursor, time_entry_id)
                return render_template("edit_time_entry.html", entry=entry, audit_rows=audit_rows)

            cursor.execute(
                """
                UPDATE dbo.TimeEntries
                SET ClockInTime = ?,
                    ClockOutTime = ?,
                    Notes = ?,
                    LastModifiedAt = UTC_TIMESTAMP(6),
                    LastModifiedByEmployeeId = ?
                WHERE TimeEntryId = ?
                """,
                updated_clock_in,
                updated_clock_out,
                notes,
                viewer_id,
                time_entry_id,
            )
            write_time_entry_audit(
                cursor,
                time_entry_id=time_entry_id,
                employee_id=entry.EmployeeId,
                action_type="ManualUpdate",
                changed_by_employee_id=viewer_id,
                change_reason=change_reason,
                old_clock_in_time=entry.ClockInTime,
                new_clock_in_time=updated_clock_in,
                old_clock_out_time=entry.ClockOutTime,
                new_clock_out_time=updated_clock_out,
                old_notes=entry.Notes,
                new_notes=notes,
                old_entry_source=entry.EntrySource,
                new_entry_source=entry.EntrySource,
            )
            conn.commit()
            flash("Time entry updated.", "success")
            return redirect(url_for("timesheet", employee_id=entry.EmployeeId))

        audit_rows = fetch_time_entry_audit(cursor, time_entry_id)

    return render_template("edit_time_entry.html", entry=entry, audit_rows=audit_rows)


@app.route("/logout")
def logout():
    if request.args.get("reason") == "timeout":
        flash("You were logged out after 10 minutes of inactivity.", "info")
    session.clear()
    return redirect(url_for("login"))


if __name__ == "__main__":
    app.run(debug=True)
