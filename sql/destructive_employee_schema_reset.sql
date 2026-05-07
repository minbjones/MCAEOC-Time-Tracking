IF OBJECT_ID('dbo.vw_EmployeeFaceStatus', 'V') IS NOT NULL DROP VIEW dbo.vw_EmployeeFaceStatus;
GO
IF OBJECT_ID('dbo.vw_EmployeeLeaveBalances', 'V') IS NOT NULL DROP VIEW dbo.vw_EmployeeLeaveBalances;
GO

IF OBJECT_ID('dbo.usp_MobileClockEvent', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_MobileClockEvent;
GO
IF OBJECT_ID('dbo.usp_RecordFaceVerificationAttempt', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_RecordFaceVerificationAttempt;
GO
IF OBJECT_ID('dbo.usp_SaveFaceTemplate', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_SaveFaceTemplate;
GO
IF OBJECT_ID('dbo.usp_RegisterMobileDevice', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_RegisterMobileDevice;
GO
IF OBJECT_ID('dbo.usp_ResetEmployeePassword', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ResetEmployeePassword;
GO
IF OBJECT_ID('dbo.usp_UpdateEmployee', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_UpdateEmployee;
GO
IF OBJECT_ID('dbo.usp_CreateEmployee', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_CreateEmployee;
GO
IF OBJECT_ID('dbo.usp_GetBiWeeklyTimesheet', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_GetBiWeeklyTimesheet;
GO
IF OBJECT_ID('dbo.usp_PostBiWeeklyLeaveAccruals', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_PostBiWeeklyLeaveAccruals;
GO
IF OBJECT_ID('dbo.usp_CancelLeaveRequest', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_CancelLeaveRequest;
GO
IF OBJECT_ID('dbo.usp_ProcessLeaveRequest', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ProcessLeaveRequest;
GO
IF OBJECT_ID('dbo.usp_RequestLeave', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_RequestLeave;
GO
IF OBJECT_ID('dbo.usp_ClockOut', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ClockOut;
GO
IF OBJECT_ID('dbo.usp_ClockIn', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ClockIn;
GO

IF OBJECT_ID('dbo.fn_GetMonthlyAccrualHours', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_GetMonthlyAccrualHours;
GO

IF OBJECT_ID('dbo.TimeEntryAudit', 'U') IS NOT NULL DROP TABLE dbo.TimeEntryAudit;
GO
IF OBJECT_ID('dbo.FaceVerificationAttempts', 'U') IS NOT NULL DROP TABLE dbo.FaceVerificationAttempts;
GO
IF OBJECT_ID('dbo.FaceTemplates', 'U') IS NOT NULL DROP TABLE dbo.FaceTemplates;
GO
IF OBJECT_ID('dbo.MobileDevices', 'U') IS NOT NULL DROP TABLE dbo.MobileDevices;
GO
IF OBJECT_ID('dbo.TimeEntries', 'U') IS NOT NULL DROP TABLE dbo.TimeEntries;
GO
IF OBJECT_ID('dbo.LeaveRequests', 'U') IS NOT NULL DROP TABLE dbo.LeaveRequests;
GO
IF OBJECT_ID('dbo.LeaveLedger', 'U') IS NOT NULL DROP TABLE dbo.LeaveLedger;
GO
IF OBJECT_ID('dbo.Employees', 'U') IS NOT NULL DROP TABLE dbo.Employees;
GO
IF OBJECT_ID('dbo.Departments', 'U') IS NOT NULL DROP TABLE dbo.Departments;
GO
IF OBJECT_ID('dbo.Roles', 'U') IS NOT NULL DROP TABLE dbo.Roles;
GO

CREATE TABLE dbo.Roles
(
    RoleId INT IDENTITY(1,1) PRIMARY KEY,
    RoleName NVARCHAR(50) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.Departments
(
    DepartmentId INT NOT NULL PRIMARY KEY,
    DepartmentName NVARCHAR(100) NOT NULL UNIQUE
);
GO

-- Departments represent funding sources in the app UI and import/export files.

CREATE TABLE dbo.Employees
(
    EmployeeId INT IDENTITY(1,1) PRIMARY KEY,
    PayrollId NVARCHAR(8) NOT NULL UNIQUE,
    DepartmentId INT NOT NULL,
    FirstName NVARCHAR(75) NOT NULL,
    LastName NVARCHAR(75) NOT NULL,
    Email NVARCHAR(255) NOT NULL UNIQUE,
    UserId NVARCHAR(150) NOT NULL UNIQUE,
    PersonalLeave BIT NOT NULL CONSTRAINT DF_Employees_PersonalLeave DEFAULT (0),
    ReportsToUserId NVARCHAR(150) NULL,
    PasswordSalt VARCHAR(32) NOT NULL,
    PasswordHash VARCHAR(64) NOT NULL,
    MustChangePassword BIT NOT NULL CONSTRAINT DF_Employees_MustChangePassword DEFAULT (1),
    RoleId INT NOT NULL,
    HireDate DATE NOT NULL,
    IsActive NVARCHAR(3) NOT NULL CONSTRAINT DF_Employees_IsActive DEFAULT ('Yes'),
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Employees_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Employees_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles(RoleId),
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentId) REFERENCES dbo.Departments(DepartmentId),
    CONSTRAINT FK_Employees_ReportsToUserId FOREIGN KEY (ReportsToUserId) REFERENCES dbo.Employees(UserId),
    CONSTRAINT CK_Employees_IsActive CHECK (IsActive IN ('Yes', 'No'))
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

CREATE TABLE dbo.MobileDevices
(
    MobileDeviceId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    DeviceIdentifier NVARCHAR(200) NOT NULL UNIQUE,
    DeviceName NVARCHAR(200) NULL,
    RegisteredAt DATETIME2 NOT NULL CONSTRAINT DF_MobileDevices_RegisteredAt DEFAULT (SYSUTCDATETIME()),
    IsActive BIT NOT NULL CONSTRAINT DF_MobileDevices_IsActive DEFAULT (1),
    CONSTRAINT FK_MobileDevices_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId)
);
GO

CREATE TABLE dbo.FaceTemplates
(
    FaceTemplateId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    TemplateData VARBINARY(MAX) NOT NULL,
    TemplateVersion NVARCHAR(50) NULL,
    EnrolledAt DATETIME2 NOT NULL CONSTRAINT DF_FaceTemplates_EnrolledAt DEFAULT (SYSUTCDATETIME()),
    EnrolledByEmployeeId INT NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_FaceTemplates_IsActive DEFAULT (1),
    CONSTRAINT FK_FaceTemplates_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_FaceTemplates_EnrolledBy FOREIGN KEY (EnrolledByEmployeeId) REFERENCES dbo.Employees(EmployeeId)
);
GO

CREATE TABLE dbo.FaceVerificationAttempts
(
    FaceVerificationAttemptId INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeId INT NOT NULL,
    MobileDeviceId INT NULL,
    VerificationResult NVARCHAR(30) NOT NULL,
    ConfidenceScore DECIMAL(8,4) NULL,
    AttemptedAt DATETIME2 NOT NULL CONSTRAINT DF_FaceVerificationAttempts_AttemptedAt DEFAULT (SYSUTCDATETIME()),
    FailureReason NVARCHAR(500) NULL,
    CONSTRAINT FK_FaceVerificationAttempts_Employees FOREIGN KEY (EmployeeId) REFERENCES dbo.Employees(EmployeeId),
    CONSTRAINT FK_FaceVerificationAttempts_Devices FOREIGN KEY (MobileDeviceId) REFERENCES dbo.MobileDevices(MobileDeviceId)
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

CREATE OR ALTER VIEW dbo.vw_EmployeeFaceStatus
AS
SELECT
    E.EmployeeId,
    E.PayrollId,
    E.FirstName,
    E.LastName,
    E.Email,
    D.DepartmentName,
    CASE WHEN FT.EmployeeId IS NULL THEN 0 ELSE 1 END AS HasActiveTemplate
FROM dbo.Employees E
INNER JOIN dbo.Departments D ON D.DepartmentId = E.DepartmentId
LEFT JOIN
(
    SELECT DISTINCT EmployeeId
    FROM dbo.FaceTemplates
    WHERE IsActive = 1
) FT ON FT.EmployeeId = E.EmployeeId;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ClockIn
    @EmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.TimeEntries WHERE EmployeeId = @EmployeeId AND ClockOutTime IS NULL)
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
    DECLARE @PersonalLeave BIT;

    SELECT @PersonalLeave = PersonalLeave
    FROM dbo.Employees
    WHERE EmployeeId = @EmployeeId;

    IF @EndDate < @StartDate
    BEGIN
        RAISERROR('End date cannot be earlier than start date.', 16, 1);
        RETURN;
    END

    IF @PersonalLeave = 1 AND @LeaveType = 'Annual'
    BEGIN
        RAISERROR('Personal-leave employees accrue Personal leave instead of Annual leave.', 16, 1);
        RETURN;
    END

    IF ISNULL(@PersonalLeave, 0) = 0 AND @LeaveType = 'Personal'
    BEGIN
        RAISERROR('Only personal-leave employees can request Personal leave.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.LeaveRequests (EmployeeId, LeaveType, StartDate, EndDate, RequestedHours, Notes)
    VALUES (@EmployeeId, @LeaveType, @StartDate, @EndDate, @RequestedHours, @Notes);
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

        INSERT INTO dbo.LeaveLedger (EmployeeId, EntryDate, LeaveType, Hours, EntryReason, ReferenceId, Notes)
        VALUES (@EmployeeId, CAST(GETDATE() AS DATE), @LeaveType, @RequestedHours * -1, 'Usage', @LeaveRequestId, 'Approved leave request');
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
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_PostBiWeeklyLeaveAccruals
    @PeriodEndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AnchorEndDate DATE = '2026-04-24';
    DECLARE @ResolvedPeriodEnd DATE = @PeriodEndDate;
    DECLARE @DaysSinceAnchor INT;
    DECLARE @ResolvedPeriodStart DATE;
    DECLARE @AccrualNote NVARCHAR(200);

    IF @ResolvedPeriodEnd IS NULL
    BEGIN
        IF CAST(GETDATE() AS DATE) < @AnchorEndDate
            RETURN;

        SET @DaysSinceAnchor = DATEDIFF(DAY, @AnchorEndDate, CAST(GETDATE() AS DATE));
        SET @ResolvedPeriodEnd = DATEADD(DAY, (@DaysSinceAnchor / 14) * 14, @AnchorEndDate);
    END

    SET @ResolvedPeriodStart = DATEADD(DAY, -13, @ResolvedPeriodEnd);
    SET @AccrualNote = CONCAT('Bi-weekly accrual for ', CONVERT(VARCHAR(10), @ResolvedPeriodStart, 23), ' through ', CONVERT(VARCHAR(10), @ResolvedPeriodEnd, 23));

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.LeaveLedger
        WHERE EntryReason = 'Accrual'
          AND EntryDate = @ResolvedPeriodEnd
          AND Notes = @AccrualNote
    )
    BEGIN
        INSERT INTO dbo.LeaveLedger (EmployeeId, EntryDate, LeaveType, Hours, EntryReason, Notes)
        SELECT
            E.EmployeeId,
            @ResolvedPeriodEnd,
            LT.LeaveType,
            CAST(ROUND((dbo.fn_GetMonthlyAccrualHours(E.HireDate) * 12.0) / 26.0, 2) AS DECIMAL(8,2)),
            'Accrual',
            @AccrualNote
        FROM dbo.Employees E
        CROSS APPLY (VALUES ('Sick'), (CASE WHEN E.PersonalLeave = 1 THEN 'Personal' ELSE 'Annual' END)) LT(LeaveType)
        WHERE E.IsActive = 'Yes'
          AND E.HireDate <= @ResolvedPeriodEnd;
    END
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
        CAST(CASE WHEN ClockOutTime IS NULL THEN 0 ELSE DATEDIFF(MINUTE, ClockInTime, ClockOutTime) / 60.0 END AS DECIMAL(8,2)) AS WorkedHours
    FROM dbo.TimeEntries
    WHERE EmployeeId = @EmployeeId
      AND CAST(ClockInTime AS DATE) BETWEEN @PeriodStartDate AND @PeriodEndDate
    ORDER BY ClockInTime;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreateEmployee
    @FirstName NVARCHAR(75),
    @LastName NVARCHAR(75),
    @Email NVARCHAR(255),
    @UserId NVARCHAR(150),
    @RoleName NVARCHAR(50) = 'User',
    @DepartmentId INT,
    @PersonalLeave BIT,
    @ReportsToUserId NVARCHAR(150) = NULL,
    @HireDate DATE,
    @PasswordSalt VARCHAR(32),
    @PasswordHash VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DepartmentPrefix VARCHAR(2) = RIGHT(CONCAT('0', CAST(@DepartmentId AS VARCHAR(10))), 2);
    DECLARE @NextSequence INT;
    DECLARE @PayrollId NVARCHAR(8);

    IF NOT EXISTS (SELECT 1 FROM dbo.Departments WHERE DepartmentId = @DepartmentId)
    BEGIN
        RAISERROR('Department was not found.', 16, 1);
        RETURN;
    END

    IF @RoleName = 'Executive Director'
        SET @ReportsToUserId = NULL;

    SELECT
        @NextSequence = ISNULL(MAX(TRY_CAST(RIGHT(PayrollId, 6) AS INT)), 0) + 1
    FROM dbo.Employees
    WHERE DepartmentId = @DepartmentId
      AND PayrollId LIKE @DepartmentPrefix + '%';

    SET @PayrollId = @DepartmentPrefix + RIGHT(REPLICATE('0', 6) + CAST(@NextSequence AS VARCHAR(6)), 6);

    INSERT INTO dbo.Employees
    (
        PayrollId, DepartmentId, FirstName, LastName, Email, UserId, PersonalLeave, ReportsToUserId,
        PasswordSalt, PasswordHash, MustChangePassword, RoleId, HireDate, IsActive
    )
    VALUES
    (
        @PayrollId, @DepartmentId, @FirstName, @LastName, @Email, @UserId, @PersonalLeave, @ReportsToUserId,
        @PasswordSalt, @PasswordHash, 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = @RoleName), @HireDate, 'Yes'
    );

    SELECT SCOPE_IDENTITY() AS EmployeeId, @PayrollId AS PayrollId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_UpdateEmployee
    @EmployeeId INT,
    @FirstName NVARCHAR(75),
    @LastName NVARCHAR(75),
    @Email NVARCHAR(255),
    @UserId NVARCHAR(150),
    @RoleName NVARCHAR(50),
    @DepartmentId INT,
    @PersonalLeave BIT,
    @ReportsToUserId NVARCHAR(150) = NULL,
    @HireDate DATE,
    @IsActive NVARCHAR(3)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Departments WHERE DepartmentId = @DepartmentId)
    BEGIN
        RAISERROR('Department was not found.', 16, 1);
        RETURN;
    END

    IF @RoleName = 'Executive Director'
        SET @ReportsToUserId = NULL;

    UPDATE dbo.Employees
    SET FirstName = @FirstName,
        LastName = @LastName,
        Email = @Email,
        UserId = @UserId,
        DepartmentId = @DepartmentId,
        PersonalLeave = @PersonalLeave,
        ReportsToUserId = @ReportsToUserId,
        RoleId = (SELECT RoleId FROM dbo.Roles WHERE RoleName = @RoleName),
        HireDate = @HireDate,
        IsActive = @IsActive
    WHERE EmployeeId = @EmployeeId;
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
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RegisterMobileDevice
    @EmployeeId INT,
    @DeviceIdentifier NVARCHAR(200),
    @DeviceName NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.MobileDevices AS target
    USING (SELECT @DeviceIdentifier AS DeviceIdentifier) AS source
    ON target.DeviceIdentifier = source.DeviceIdentifier
    WHEN MATCHED THEN
        UPDATE SET EmployeeId = @EmployeeId, DeviceName = @DeviceName, IsActive = 1
    WHEN NOT MATCHED THEN
        INSERT (EmployeeId, DeviceIdentifier, DeviceName) VALUES (@EmployeeId, @DeviceIdentifier, @DeviceName);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SaveFaceTemplate
    @EmployeeId INT,
    @TemplateData VARBINARY(MAX),
    @TemplateVersion NVARCHAR(50) = NULL,
    @EnrolledByEmployeeId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.FaceTemplates
    SET IsActive = 0
    WHERE EmployeeId = @EmployeeId;

    INSERT INTO dbo.FaceTemplates (EmployeeId, TemplateData, TemplateVersion, EnrolledByEmployeeId, IsActive)
    VALUES (@EmployeeId, @TemplateData, @TemplateVersion, @EnrolledByEmployeeId, 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RecordFaceVerificationAttempt
    @EmployeeId INT,
    @MobileDeviceId INT = NULL,
    @VerificationResult NVARCHAR(30),
    @ConfidenceScore DECIMAL(8,4) = NULL,
    @FailureReason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.FaceVerificationAttempts
    (
        EmployeeId, MobileDeviceId, VerificationResult, ConfidenceScore, FailureReason
    )
    VALUES
    (
        @EmployeeId, @MobileDeviceId, @VerificationResult, @ConfidenceScore, @FailureReason
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_MobileClockEvent
    @EmployeeId INT,
    @ClockAction NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF @ClockAction = 'In'
        EXEC dbo.usp_ClockIn @EmployeeId = @EmployeeId;
    ELSE
        EXEC dbo.usp_ClockOut @EmployeeId = @EmployeeId;
END;
GO

INSERT INTO dbo.Roles (RoleName)
VALUES ('Owner'), ('Executive Director'), ('Director'), ('Manager'), ('Leave Manager'), ('User');
GO

INSERT INTO dbo.Departments (DepartmentId, DepartmentName)
VALUES
(20, 'Head Start-2'),
(21, 'ADMIN'),
(22, 'Head Start'),
(24, 'ABC'),
(44, 'CSBG'),
(50, 'HIPPY'),
(51, 'HEAP/LIHEAP'),
(99, 'FINANCE');
GO

DECLARE @TempPassword NVARCHAR(100) = 'Welcome1!';

INSERT INTO dbo.Employees
(
    PayrollId, DepartmentId, FirstName, LastName, Email, UserId, PersonalLeave, ReportsToUserId,
    PasswordSalt, PasswordHash, MustChangePassword, RoleId, HireDate, IsActive
)
VALUES
('22000001', 22, 'Priscilla', 'Johnson', 'priscilla.johnson@mcaeoc.org', 'priscilla.johnson', 0, 'shirley.pulliam', 'A1B2C3D4E5F60708', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('A1B2C3D4E5F60708', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'), '2024-01-15', 'Yes'),
('22000002', 22, 'Decarla', 'Rinkines', 'decarla.rinkines@mcaeoc.org', 'decarla.rinkines', 0, 'shirley.pulliam', 'B1C2D3E4F5060708', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('B1C2D3E4F5060708', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'), '2022-06-01', 'Yes'),
('22000003', 22, 'Juanita', 'Medlin', 'juanita.medlin@mcaeoc.org', 'juanita.medlin', 0, 'shirley.pulliam', 'C1D2E3F405060708', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('C1D2E3F405060708', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'), '2020-09-14', 'Yes'),
('22000004', 22, 'Clark', 'Phillips', 'clark.phillips@mcaeoc.org', 'clark.phillips', 0, 'shirley.pulliam', 'D1E2F30405060708', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('D1E2F30405060708', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'), '2018-03-20', 'Yes'),
('22000005', 22, 'Shirley', 'Pulliam', 'shirley.pulliam@mcaeoc.org', 'shirley.pulliam', 1, 'blanton.jones', 'E1F2030405060708', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('E1F2030405060708', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Manager'), '2017-04-10', 'Yes'),
('21000001', 21, 'Blanton', 'Jones', 'blanton.jones@mcaeoc.org', 'blanton.jones', 0, NULL, 'F102030405060708', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('F102030405060708', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Owner'), '2015-07-01', 'Yes'),
('22000006', 22, 'Jacqueline', 'Burton', 'jacqueline.burton@mcaeoc.org', 'jacqueline.burton', 1, 'shirley.pulliam', '0A1B2C3D4E5F6071', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('0A1B2C3D4E5F6071', @TempPassword)), 2), 1, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'User'), '2025-02-03', 'Yes'),
('99000001', 99, 'Admin', 'User', 'admin@mcaeoc.org', 'admin', 0, NULL, '14002008BLANTON1', '7375A6565E6182969595C2F73146280E6DF6155BEBCDB4DDCE2A1F01944FE91A', 0, (SELECT RoleId FROM dbo.Roles WHERE RoleName = 'Owner'), '2015-07-01', 'Yes');
GO

EXEC dbo.usp_PostBiWeeklyLeaveAccruals @PeriodEndDate = '2026-04-24';
GO
