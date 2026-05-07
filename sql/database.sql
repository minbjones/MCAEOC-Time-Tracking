USE master;
GO

IF DB_ID('EmployeeTimeTracking') IS NOT NULL
BEGIN
    ALTER DATABASE EmployeeTimeTracking SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EmployeeTimeTracking;
END
GO

CREATE DATABASE EmployeeTimeTracking;
GO

USE EmployeeTimeTracking;
GO

CREATE TABLE dbo.Roles
(
    RoleId INT IDENTITY(1,1) PRIMARY KEY,
    RoleName NVARCHAR(50) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.Employees
(
    EmployeeId INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(75) NOT NULL,
    LastName NVARCHAR(75) NOT NULL,
    FullName NVARCHAR(150) NOT NULL,
    Username NVARCHAR(60) NOT NULL UNIQUE,
    IsHeadStart BIT NOT NULL CONSTRAINT DF_Employees_IsHeadStart DEFAULT (0),
    ReportsToEmployeeId INT NULL,
    PasswordSalt VARCHAR(32) NOT NULL,
    PasswordHash VARCHAR(64) NOT NULL,
    MustChangePassword BIT NOT NULL CONSTRAINT DF_Employees_MustChangePassword DEFAULT (1),
    RoleId INT NOT NULL,
    HireDate DATE NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_Employees_IsActive DEFAULT (1),
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Employees_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Employees_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles(RoleId),
    CONSTRAINT FK_Employees_ReportsTo FOREIGN KEY (ReportsToEmployeeId) REFERENCES dbo.Employees(EmployeeId)
);
GO

CREATE TABLE dbo.TimeEntries
(
    TimeEntryId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    ClockInTime DATETIME2 NOT NULL,
    ClockOutTime DATETIME2 NULL,
    Notes NVARCHAR(500) NULL,
    EntrySource NVARCHAR(20) NOT NULL CONSTRAINT DF_TimeEntries_EntrySource DEFAULT ('Clock'),
    CreatedByEmployeeId INT NULL,
    LastModifiedAt DATETIME2 NULL,
    LastModifiedByEmployeeId INT NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_TimeEntries_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_TimeEntries_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_TimeEntries_CreatedByEmployee FOREIGN KEY (CreatedByEmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_TimeEntries_LastModifiedByEmployee FOREIGN KEY (LastModifiedByEmployeeId) REFERENCES dbo.Employees(EmployeeId)
);
GO

CREATE TABLE dbo.TimeEntryAudit
(
    TimeEntryAuditId INT IDENTITY(1,1) PRIMARY KEY,
    TimeEntryId INT NOT NULL,
    EmployeeId INT NOT NULL,
    ActionType NVARCHAR(30) NOT NULL,
    ChangeReason NVARCHAR(500) NOT NULL,
    OldClockInTime DATETIME2 NULL,
    NewClockInTime DATETIME2 NULL,
    OldClockOutTime DATETIME2 NULL,
    NewClockOutTime DATETIME2 NULL,
    OldNotes NVARCHAR(500) NULL,
    NewNotes NVARCHAR(500) NULL,
    OldEntrySource NVARCHAR(20) NULL,
    NewEntrySource NVARCHAR(20) NULL,
    ChangedByEmployeeId INT NOT NULL,
    ChangedAt DATETIME2 NOT NULL CONSTRAINT DF_TimeEntryAudit_ChangedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_TimeEntryAudit_TimeEntries FOREIGN KEY (TimeEntryId) REFERENCES dbo.TimeEntries(TimeEntryId),
    CONSTRAINT FK_TimeEntryAudit_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_TimeEntryAudit_ChangedBy FOREIGN KEY (ChangedByEmployeeId) REFERENCES dbo.Employees(EmployeeId)
);
GO

CREATE TABLE dbo.LeaveRequests
(
    LeaveRequestId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    LeaveType NVARCHAR(20) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    RequestedHours DECIMAL(8,2) NOT NULL,
    ApprovalStatus NVARCHAR(20) NOT NULL CONSTRAINT DF_LeaveRequests_ApprovalStatus DEFAULT ('Pending'),
    Notes NVARCHAR(500) NULL,
    RequestedAt DATETIME2 NOT NULL CONSTRAINT DF_LeaveRequests_RequestedAt DEFAULT (SYSUTCDATETIME()),
    ApprovedByEmployeeId INT NULL,
    ApprovedAt DATETIME2 NULL,
    CONSTRAINT FK_LeaveRequests_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_LeaveRequests_Approvers FOREIGN KEY (ApprovedByEmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT CK_LeaveRequests_Type CHECK (LeaveType IN ('Annual', 'Sick', 'Personal')),
    CONSTRAINT CK_LeaveRequests_Status CHECK (ApprovalStatus IN ('Pending', 'Approved', 'Denied', 'Canceled'))
);
GO

CREATE TABLE dbo.LeaveLedger
(
    LeaveLedgerId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    EntryDate DATE NOT NULL,
    LeaveType NVARCHAR(20) NOT NULL,
    Hours DECIMAL(8,2) NOT NULL,
    EntryReason NVARCHAR(30) NOT NULL,
    ReferenceId INT NULL,
    Notes NVARCHAR(500) NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_LeaveLedger_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_LeaveLedger_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT CK_LeaveLedger_Type CHECK (LeaveType IN ('Annual', 'Sick', 'Personal')),
    CONSTRAINT CK_LeaveLedger_Reason CHECK (EntryReason IN ('Accrual', 'Usage', 'Adjustment'))
);
GO

CREATE OR ALTER FUNCTION dbo.fn_GetMonthlyAccrualHours
(
    @HireDate DATE
)
RETURNS DECIMAL(8,2)
AS
BEGIN
    DECLARE @YearsEmployed INT = DATEDIFF(YEAR, @HireDate, CAST(GETDATE() AS DATE));

    IF DATEADD(YEAR, @YearsEmployed, @HireDate) > CAST(GETDATE() AS DATE)
        SET @YearsEmployed = @YearsEmployed - 1;

    RETURN
    (
        CASE
            WHEN @YearsEmployed < 3 THEN 10.00
            WHEN @YearsEmployed < 5 THEN 12.00
            ELSE 14.00
        END
    );
END;
GO

CREATE OR ALTER VIEW dbo.vw_EmployeeLeaveBalances
AS
SELECT
    E.EmployeeId,
    SUM(CASE WHEN L.LeaveType = 'Annual' THEN L.Hours ELSE 0 END) AS AnnualLeaveHours,
    SUM(CASE WHEN L.LeaveType = 'Sick' THEN L.Hours ELSE 0 END) AS SickLeaveHours,
    SUM(CASE WHEN L.LeaveType = 'Personal' THEN L.Hours ELSE 0 END) AS PersonalLeaveHours
FROM dbo.Employees E
LEFT JOIN dbo.LeaveLedger L ON L.EmployeeId = E.EmployeeId
GROUP BY E.EmployeeId;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ClockIn
    @EmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.TimeEntries
        WHERE EmployeeId = @EmployeeId
          AND ClockOutTime IS NULL
    )
    BEGIN
        RAISERROR('Employee is already clocked in.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.TimeEntries (EmployeeId, ClockInTime)
    VALUES (@EmployeeId, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ClockOut
    @EmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE TOP (1) dbo.TimeEntries
    SET ClockOutTime = SYSDATETIME()
    WHERE EmployeeId = @EmployeeId
      AND ClockOutTime IS NULL;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Employee is not currently clocked in.', 16, 1);
        RETURN;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RequestLeave
    @EmployeeId INT,
    @LeaveType NVARCHAR(20),
    @StartDate DATE,
    @EndDate DATE,
    @RequestedHours DECIMAL(8,2),
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsHeadStart BIT;

    SELECT @IsHeadStart = IsHeadStart
    FROM dbo.Employees
    WHERE EmployeeId = @EmployeeId;

    IF @EndDate < @StartDate
    BEGIN
        RAISERROR('End date cannot be earlier than start date.', 16, 1);
        RETURN;
    END

    IF @IsHeadStart = 1 AND @LeaveType = 'Annual'
    BEGIN
        RAISERROR('Head Start employees accrue Personal leave instead of Annual leave.', 16, 1);
        RETURN;
    END

    IF ISNULL(@IsHeadStart, 0) = 0 AND @LeaveType = 'Personal'
    BEGIN
        RAISERROR('Only Head Start employees can request Personal leave.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.LeaveRequests
    (
        EmployeeId,
        LeaveType,
        StartDate,
        EndDate,
        RequestedHours,
        Notes
    )
    VALUES
    (
        @EmployeeId,
        @LeaveType,
        @StartDate,
        @EndDate,
        @RequestedHours,
        @Notes
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ProcessLeaveRequest
    @LeaveRequestId INT,
    @ApprovalStatus NVARCHAR(20),
    @ApprovedByEmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EmployeeId INT;
    DECLARE @LeaveType NVARCHAR(20);
    DECLARE @RequestedHours DECIMAL(8,2);
    DECLARE @CurrentBalance DECIMAL(8,2);

    SELECT
        @EmployeeId = EmployeeId,
        @LeaveType = LeaveType,
        @RequestedHours = RequestedHours
    FROM dbo.LeaveRequests
    WHERE LeaveRequestId = @LeaveRequestId
      AND ApprovalStatus = 'Pending';

    IF @EmployeeId IS NULL
    BEGIN
        RAISERROR('Leave request was not found or is already processed.', 16, 1);
        RETURN;
    END

    IF @ApprovalStatus = 'Approved'
    BEGIN
        SELECT
            @CurrentBalance =
                CASE
                    WHEN @LeaveType = 'Annual' THEN AnnualLeaveHours
                    WHEN @LeaveType = 'Personal' THEN PersonalLeaveHours
                    ELSE SickLeaveHours
                END
        FROM dbo.vw_EmployeeLeaveBalances
        WHERE EmployeeId = @EmployeeId;

        IF ISNULL(@CurrentBalance, 0) < @RequestedHours
        BEGIN
            RAISERROR('Insufficient leave balance.', 16, 1);
            RETURN;
        END

        INSERT INTO dbo.LeaveLedger
        (
            EmployeeId,
            EntryDate,
            LeaveType,
            Hours,
            EntryReason,
            ReferenceId,
            Notes
        )
        VALUES
        (
            @EmployeeId,
            CAST(GETDATE() AS DATE),
            @LeaveType,
            @RequestedHours * -1,
            'Usage',
            @LeaveRequestId,
            'Approved leave request'
        );
    END

    UPDATE dbo.LeaveRequests
    SET ApprovalStatus = @ApprovalStatus,
        ApprovedByEmployeeId = @ApprovedByEmployeeId,
        ApprovedAt = SYSDATETIME()
    WHERE LeaveRequestId = @LeaveRequestId;
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

CREATE OR ALTER PROCEDURE dbo.usp_PostMonthlyLeaveAccruals
    @AccrualDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EffectiveDate DATE = ISNULL(@AccrualDate, EOMONTH(GETDATE()));

    INSERT INTO dbo.LeaveLedger
    (
        EmployeeId,
        EntryDate,
        LeaveType,
        Hours,
        EntryReason,
        Notes
    )
    SELECT
        E.EmployeeId,
        @EffectiveDate,
        LT.LeaveType,
        dbo.fn_GetMonthlyAccrualHours(E.HireDate),
        'Accrual',
        CONCAT('Monthly accrual for ', YEAR(@EffectiveDate), '-', RIGHT(CONCAT('0', MONTH(@EffectiveDate)), 2))
    FROM dbo.Employees E
    CROSS APPLY
    (
        VALUES
            ('Sick'),
            (CASE WHEN E.IsHeadStart = 1 THEN 'Personal' ELSE 'Annual' END)
    ) LT(LeaveType)
    WHERE E.IsActive = 1
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.LeaveLedger L
          WHERE L.EmployeeId = E.EmployeeId
            AND L.LeaveType = LT.LeaveType
            AND L.EntryReason = 'Accrual'
            AND YEAR(L.EntryDate) = YEAR(@EffectiveDate)
            AND MONTH(L.EntryDate) = MONTH(@EffectiveDate)
      );
END;
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
        Notes,
        EntrySource,
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

INSERT INTO dbo.Roles (RoleName)
VALUES ('Owner'),
       ('Executive Director'),
       ('Director'),
       ('Manager'),
       ('Leave Manager'),
       ('User');
GO

DECLARE @TempPassword NVARCHAR(100) = 'Welcome1!';

INSERT INTO dbo.Employees
(
    FirstName,
    LastName,
    FullName,
    Username,
    IsHeadStart,
    PasswordSalt,
    PasswordHash,
    MustChangePassword,
    RoleId,
    HireDate
)
VALUES
(
    'Priscilla',
    'Johnson',
    'Priscilla Johnson',
    'priscilla.johnson',
    0,
    'A1B2C3D4E5F60708',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('A1B2C3D4E5F60708', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'),
    '2024-01-15'
),
(
    'Decarla',
    'Rinkines',
    'Decarla Rinkines',
    'decarla.rinkines',
    0,
    'B1C2D3E4F5060708',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('B1C2D3E4F5060708', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'),
    '2022-06-01'
),
(
    'Juanita',
    'Medlin',
    'Juanita Medlin',
    'juanita.medlin',
    0,
    'C1D2E3F405060708',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('C1D2E3F405060708', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'),
    '2020-09-14'
),
(
    'Clark',
    'Phillips',
    'Clark Phillips',
    'clark.phillips',
    0,
    'D1E2F30405060708',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('D1E2F30405060708', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'),
    '2018-03-20'
),
(
    'Shirley',
    'Pulliam',
    'Shirley Pulliam',
    'shirley.pulliam',
    1,
    'E1F2030405060708',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('E1F2030405060708', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Manager'),
    '2017-04-10'
),
(
    'Blanton',
    'Jones',
    'Blanton Jones',
    'blanton.jones',
    0,
    'F102030405060708',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('F102030405060708', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Owner'),
    '2015-07-01'
),
(
    'Jacqueline',
    'Burton',
    'Jacqueline Burton',
    'jacqueline.burton',
    1,
    '0A1B2C3D4E5F6071',
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('0A1B2C3D4E5F6071', @TempPassword)), 2),
    1,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'),
    '2025-02-03'
),
(
    'Admin',
    'User',
    'Admin',
    'admin',
    0,
    '14002008BLANTON1',
    '7375A6565E6182969595C2F73146280E6DF6155BEBCDB4DDCE2A1F01944FE91A',
    0,
    (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Owner'),
    '2015-07-01'
);
GO

EXEC dbo.usp_PostMonthlyLeaveAccruals @AccrualDate = '2026-03-31';
GO
