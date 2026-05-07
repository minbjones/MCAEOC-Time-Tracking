USE EmployeeTimeTracking;
GO

IF COL_LENGTH('dbo.Employees', 'IsHeadStart') IS NULL
BEGIN
    ALTER TABLE dbo.Employees
    ADD IsHeadStart BIT NOT NULL
        CONSTRAINT DF_Employees_IsHeadStart DEFAULT (0);
END
GO

IF COL_LENGTH('dbo.Employees', 'ReportsToEmployeeId') IS NULL
BEGIN
    ALTER TABLE dbo.Employees
    ADD ReportsToEmployeeId INT NULL;
END
GO

IF COL_LENGTH('dbo.Employees', 'FirstName') IS NULL
BEGIN
    ALTER TABLE dbo.Employees
    ADD FirstName NVARCHAR(75) NULL;
END
GO

IF COL_LENGTH('dbo.Employees', 'LastName') IS NULL
BEGIN
    ALTER TABLE dbo.Employees
    ADD LastName NVARCHAR(75) NULL;
END
GO

UPDATE dbo.Employees
SET FirstName = LTRIM(RTRIM(CASE WHEN CHARINDEX(' ', FullName) > 0 THEN LEFT(FullName, LEN(FullName) - CHARINDEX(' ', REVERSE(FullName))) ELSE FullName END)),
    LastName = LTRIM(RTRIM(CASE WHEN CHARINDEX(' ', FullName) > 0 THEN RIGHT(FullName, CHARINDEX(' ', REVERSE(FullName)) - 1) ELSE '' END))
WHERE FirstName IS NULL
   OR LastName IS NULL;
GO

ALTER TABLE dbo.Employees ALTER COLUMN FirstName NVARCHAR(75) NOT NULL;
GO

ALTER TABLE dbo.Employees ALTER COLUMN LastName NVARCHAR(75) NOT NULL;
GO

IF OBJECT_ID('dbo.FK_Employees_ReportsTo', 'F') IS NULL
BEGIN
    ALTER TABLE dbo.Employees
    ADD CONSTRAINT FK_Employees_ReportsTo FOREIGN KEY (ReportsToEmployeeId) REFERENCES dbo.Employees(EmployeeId);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_LeaveRequests_Status'
      AND parent_object_id = OBJECT_ID('dbo.LeaveRequests')
)
BEGIN
    ALTER TABLE dbo.LeaveRequests
    ADD CONSTRAINT CK_LeaveRequests_Status CHECK (ApprovalStatus IN ('Pending', 'Approved', 'Denied', 'Canceled'));
END
ELSE
BEGIN
    ALTER TABLE dbo.LeaveRequests DROP CONSTRAINT CK_LeaveRequests_Status;
    ALTER TABLE dbo.LeaveRequests
    ADD CONSTRAINT CK_LeaveRequests_Status CHECK (ApprovalStatus IN ('Pending', 'Approved', 'Denied', 'Canceled'));
END
GO

IF COL_LENGTH('dbo.Employees', 'Workflow') IS NOT NULL
BEGIN
    ALTER TABLE dbo.Employees
    DROP COLUMN Workflow;
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Executive Director')
    INSERT INTO dbo.Roles (RoleName) VALUES ('Executive Director');
GO

IF EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Admin')
   AND NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Director')
BEGIN
    UPDATE dbo.Roles
    SET RoleName = 'Director'
    WHERE RoleName = 'Admin';
END
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Director')
BEGIN
    INSERT INTO dbo.Roles (RoleName) VALUES ('Director');
END
GO

IF EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Admin')
   AND EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Director')
BEGIN
    UPDATE dbo.Employees
    SET RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Director')
    WHERE RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Admin');
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreateEmployee
    @FirstName NVARCHAR(75),
    @LastName NVARCHAR(75),
    @Username NVARCHAR(60),
    @RoleName NVARCHAR(50) = 'User',
    @IsHeadStart BIT,
    @ReportsToEmployeeId INT = NULL,
    @HireDate DATE,
    @PasswordSalt VARCHAR(32),
    @PasswordHash VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = @RoleName)
    BEGIN
        RAISERROR('Invalid role name.', 16, 1);
        RETURN;
    END

    IF @RoleName = 'Executive Director'
        SET @ReportsToEmployeeId = NULL;

    INSERT INTO dbo.Employees
    (
        FirstName,
        LastName,
        FullName,
        Username,
        IsHeadStart,
        ReportsToEmployeeId,
        PasswordSalt,
        PasswordHash,
        MustChangePassword,
        RoleId,
        HireDate
    )
    VALUES
    (
        @FirstName,
        @LastName,
        LTRIM(RTRIM(CONCAT(@FirstName, ' ', @LastName))),
        @Username,
        @IsHeadStart,
        @ReportsToEmployeeId,
        @PasswordSalt,
        @PasswordHash,
        1,
        (SELECT RoleId FROM dbo.Roles WHERE RoleName = @RoleName),
        @HireDate
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_UpdateEmployee
    @EmployeeId INT,
    @FirstName NVARCHAR(75),
    @LastName NVARCHAR(75),
    @Username NVARCHAR(60),
    @RoleName NVARCHAR(50),
    @IsHeadStart BIT,
    @ReportsToEmployeeId INT = NULL,
    @HireDate DATE,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = @RoleName)
    BEGIN
        RAISERROR('Invalid role name.', 16, 1);
        RETURN;
    END

    IF @RoleName = 'Executive Director'
        SET @ReportsToEmployeeId = NULL;

    UPDATE dbo.Employees
    SET FirstName = @FirstName,
        LastName = @LastName,
        FullName = LTRIM(RTRIM(CONCAT(@FirstName, ' ', @LastName))),
        Username = @Username,
        IsHeadStart = @IsHeadStart,
        ReportsToEmployeeId = @ReportsToEmployeeId,
        RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = @RoleName),
        HireDate = @HireDate,
        IsActive = @IsActive
    WHERE EmployeeId = @EmployeeId;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Employee not found.', 16, 1);
        RETURN;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ResetEmployeePassword
    @EmployeeId INT,
    @PasswordSalt VARCHAR(32),
    @PasswordHash VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Employees
    SET PasswordSalt = @PasswordSalt,
        PasswordHash = @PasswordHash,
        MustChangePassword = 1
    WHERE EmployeeId = @EmployeeId;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Employee not found.', 16, 1);
        RETURN;
    END
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Employees WHERE Username = 'admin')
BEGIN
    INSERT INTO dbo.Employees
    (
        FullName,
        Username,
        IsHeadStart,
        ReportsToEmployeeId,
        PasswordSalt,
        PasswordHash,
        MustChangePassword,
        RoleId,
        HireDate,
        IsActive
    )
    VALUES
    (
        'Admin',
        'admin',
        0,
        NULL,
        '14002008BLANTON1',
        '7375A6565E6182969595C2F73146280E6DF6155BEBCDB4DDCE2A1F01944FE91A',
        0,
        (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Owner'),
        '2015-07-01',
        1
    );
END
ELSE
BEGIN
    UPDATE dbo.Employees
    SET FullName = 'Admin',
        PasswordSalt = '14002008BLANTON1',
        PasswordHash = '7375A6565E6182969595C2F73146280E6DF6155BEBCDB4DDCE2A1F01944FE91A',
        MustChangePassword = 0,
        RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Owner'),
        ReportsToEmployeeId = NULL,
        IsActive = 1
    WHERE Username = 'admin';
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetBiWeeklyTimesheet
    @EmployeeId INT,
    @PeriodStartDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodEndDate DATE = DATEADD(DAY, 13, @PeriodStartDate);

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
        ) AS WorkedHours
    FROM dbo.TimeEntries
    WHERE EmployeeId = @EmployeeId
      AND CAST(ClockInTime AS DATE) BETWEEN @PeriodStartDate AND @PeriodEndDate
    ORDER BY ClockInTime;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CancelLeaveRequest
    @LeaveRequestId INT,
    @EmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.LeaveRequests
    SET ApprovalStatus = 'Canceled',
        ApprovedByEmployeeId = @EmployeeId,
        ApprovedAt = SYSDATETIME(),
        Notes = COALESCE(Notes + ' | ', '') + 'Canceled by employee'
    WHERE LeaveRequestId = @LeaveRequestId
      AND EmployeeId = @EmployeeId
      AND ApprovalStatus = 'Pending';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Only pending leave requests can be cancelled by the requesting employee.', 16, 1);
        RETURN;
    END
END;
GO
