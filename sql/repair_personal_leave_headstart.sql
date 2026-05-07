USE EmployeeTimeTracking;
GO

IF COL_LENGTH('dbo.Employees', 'IsHeadStart') IS NULL
BEGIN
    ALTER TABLE dbo.Employees
    ADD IsHeadStart BIT NOT NULL
        CONSTRAINT DF_Employees_IsHeadStart DEFAULT (0);
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

IF COL_LENGTH('dbo.Employees', 'Workflow') IS NOT NULL
BEGIN
    ALTER TABLE dbo.Employees
    DROP COLUMN Workflow;
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_LeaveRequests_Type'
      AND parent_object_id = OBJECT_ID('dbo.LeaveRequests')
)
BEGIN
    ALTER TABLE dbo.LeaveRequests
    ADD CONSTRAINT CK_LeaveRequests_Type CHECK (LeaveType IN ('Annual', 'Sick', 'Personal'));
END
ELSE
BEGIN
    ALTER TABLE dbo.LeaveRequests DROP CONSTRAINT CK_LeaveRequests_Type;
    ALTER TABLE dbo.LeaveRequests
    ADD CONSTRAINT CK_LeaveRequests_Type CHECK (LeaveType IN ('Annual', 'Sick', 'Personal'));
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

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_LeaveLedger_Type'
      AND parent_object_id = OBJECT_ID('dbo.LeaveLedger')
)
BEGIN
    ALTER TABLE dbo.LeaveLedger
    ADD CONSTRAINT CK_LeaveLedger_Type CHECK (LeaveType IN ('Annual', 'Sick', 'Personal'));
END
ELSE
BEGIN
    ALTER TABLE dbo.LeaveLedger DROP CONSTRAINT CK_LeaveLedger_Type;
    ALTER TABLE dbo.LeaveLedger
    ADD CONSTRAINT CK_LeaveLedger_Type CHECK (LeaveType IN ('Annual', 'Sick', 'Personal'));
END
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

CREATE OR ALTER PROCEDURE dbo.usp_CreateEmployee
    @FirstName NVARCHAR(75),
    @LastName NVARCHAR(75),
    @Username NVARCHAR(60),
    @RoleName NVARCHAR(50) = 'User',
    @IsHeadStart BIT,
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
        @FirstName,
        @LastName,
        LTRIM(RTRIM(CONCAT(@FirstName, ' ', @LastName))),
        @Username,
        @IsHeadStart,
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

    UPDATE dbo.Employees
    SET FirstName = @FirstName,
        LastName = @LastName,
        FullName = LTRIM(RTRIM(CONCAT(@FirstName, ' ', @LastName))),
        Username = @Username,
        IsHeadStart = @IsHeadStart,
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
