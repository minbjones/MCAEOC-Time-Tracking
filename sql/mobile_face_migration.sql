USE EmployeeTimeTracking;
GO

IF COL_LENGTH('dbo.TimeEntries', 'ClockMethod') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD ClockMethod NVARCHAR(30) NOT NULL
        CONSTRAINT DF_TimeEntries_ClockMethod DEFAULT ('WebManual');
END
GO

IF COL_LENGTH('dbo.TimeEntries', 'SourceDeviceId') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD SourceDeviceId INT NULL;
END
GO

IF COL_LENGTH('dbo.TimeEntries', 'VerificationAttemptId') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD VerificationAttemptId INT NULL;
END
GO

IF COL_LENGTH('dbo.TimeEntries', 'Latitude') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD Latitude DECIMAL(9,6) NULL;
END
GO

IF COL_LENGTH('dbo.TimeEntries', 'Longitude') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD Longitude DECIMAL(9,6) NULL;
END
GO

IF OBJECT_ID('dbo.MobileDevices', 'U') IS NULL
CREATE TABLE dbo.MobileDevices
(
    MobileDeviceId INT IDENTITY(1,1) PRIMARY KEY,
    PayrollId INT NOT NULL,
    DeviceIdentifier NVARCHAR(150) NOT NULL,
    DeviceName NVARCHAR(150) NULL,
    Platform NVARCHAR(30) NOT NULL CONSTRAINT DF_MobileDevices_Platform DEFAULT ('Android'),
    IsTrusted BIT NOT NULL CONSTRAINT DF_MobileDevices_IsTrusted DEFAULT (1),
    RegisteredAt DATETIME2 NOT NULL CONSTRAINT DF_MobileDevices_RegisteredAt DEFAULT (SYSUTCDATETIME()),
    LastSeenAt DATETIME2 NULL,
    CONSTRAINT FK_MobileDevices_Employees FOREIGN KEY (PayrollId) REFERENCES dbo.Employees(PayrollId),
    CONSTRAINT UQ_MobileDevices_DeviceIdentifier UNIQUE (DeviceIdentifier)
);
GO

IF OBJECT_ID('dbo.FaceTemplates', 'U') IS NULL
CREATE TABLE dbo.FaceTemplates
(
    FaceTemplateId INT IDENTITY(1,1) PRIMARY KEY,
    PayrollId INT NOT NULL,
    ProviderName NVARCHAR(50) NOT NULL CONSTRAINT DF_FaceTemplates_ProviderName DEFAULT ('DeepFace'),
    ProviderPersonGroupId NVARCHAR(64) NULL,
    ProviderPersonId NVARCHAR(64) NULL,
    ProviderPersistedFaceId NVARCHAR(64) NULL,
    TemplateVersion NVARCHAR(30) NOT NULL,
    TemplateData VARBINARY(MAX) NOT NULL,
    EmbeddingJson NVARCHAR(MAX) NULL,
    EmbeddingDimensions INT NULL,
    ModelName NVARCHAR(50) NULL,
    DetectorBackend NVARCHAR(50) NULL,
    EncryptionKeyLabel NVARCHAR(100) NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_FaceTemplates_IsActive DEFAULT (1),
    EnrolledAt DATETIME2 NOT NULL CONSTRAINT DF_FaceTemplates_EnrolledAt DEFAULT (SYSUTCDATETIME()),
    EnrolledByPayrollId INT NULL,
    Notes NVARCHAR(500) NULL,
    CONSTRAINT FK_FaceTemplates_Employees FOREIGN KEY (PayrollId) REFERENCES dbo.Employees(PayrollId),
    CONSTRAINT FK_FaceTemplates_EnrolledBy FOREIGN KEY (EnrolledByPayrollId) REFERENCES dbo.Employees(PayrollId)
);
GO

IF COL_LENGTH('dbo.FaceTemplates', 'EmbeddingJson') IS NULL
BEGIN
    ALTER TABLE dbo.FaceTemplates ADD EmbeddingJson NVARCHAR(MAX) NULL;
END
GO

IF COL_LENGTH('dbo.FaceTemplates', 'EmbeddingDimensions') IS NULL
BEGIN
    ALTER TABLE dbo.FaceTemplates ADD EmbeddingDimensions INT NULL;
END
GO

IF COL_LENGTH('dbo.FaceTemplates', 'ModelName') IS NULL
BEGIN
    ALTER TABLE dbo.FaceTemplates ADD ModelName NVARCHAR(50) NULL;
END
GO

IF COL_LENGTH('dbo.FaceTemplates', 'DetectorBackend') IS NULL
BEGIN
    ALTER TABLE dbo.FaceTemplates ADD DetectorBackend NVARCHAR(50) NULL;
END
GO

IF OBJECT_ID('dbo.FaceVerificationAttempts', 'U') IS NULL
CREATE TABLE dbo.FaceVerificationAttempts
(
    FaceVerificationAttemptId INT IDENTITY(1,1) PRIMARY KEY,
    PayrollId INT NULL,
    MobileDeviceId INT NULL,
    VerificationPurpose NVARCHAR(30) NOT NULL,
    VerificationStatus NVARCHAR(20) NOT NULL,
    ConfidenceScore DECIMAL(5,4) NULL,
    LivenessScore DECIMAL(5,4) NULL,
    DistanceScore DECIMAL(8,6) NULL,
    FailureReason NVARCHAR(200) NULL,
    CapturedAt DATETIME2 NOT NULL CONSTRAINT DF_FaceVerificationAttempts_CapturedAt DEFAULT (SYSUTCDATETIME()),
    ProviderReference NVARCHAR(120) NULL,
    CONSTRAINT FK_FaceVerificationAttempts_Employees FOREIGN KEY (PayrollId) REFERENCES dbo.Employees(PayrollId),
    CONSTRAINT FK_FaceVerificationAttempts_MobileDevices FOREIGN KEY (MobileDeviceId) REFERENCES dbo.MobileDevices(MobileDeviceId),
    CONSTRAINT CK_FaceVerificationAttempts_Purpose CHECK (VerificationPurpose IN ('Enrollment', 'ClockIn', 'ClockOut', 'Identify')),
    CONSTRAINT CK_FaceVerificationAttempts_Status CHECK (VerificationStatus IN ('Passed', 'Failed', 'Review'))
);
GO

IF OBJECT_ID('dbo.CK_FaceVerificationAttempts_Purpose', 'C') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FaceVerificationAttempts DROP CONSTRAINT CK_FaceVerificationAttempts_Purpose;
END
GO

ALTER TABLE dbo.FaceVerificationAttempts
ADD CONSTRAINT CK_FaceVerificationAttempts_Purpose
CHECK (VerificationPurpose IN ('Enrollment', 'ClockIn', 'ClockOut', 'Identify'));
GO

IF OBJECT_ID('dbo.CK_FaceVerificationAttempts_Status', 'C') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FaceVerificationAttempts DROP CONSTRAINT CK_FaceVerificationAttempts_Status;
END
GO

ALTER TABLE dbo.FaceVerificationAttempts
ADD CONSTRAINT CK_FaceVerificationAttempts_Status
CHECK (VerificationStatus IN ('Passed', 'Failed', 'Review'));
GO

IF COL_LENGTH('dbo.FaceVerificationAttempts', 'DistanceScore') IS NULL
BEGIN
    ALTER TABLE dbo.FaceVerificationAttempts ADD DistanceScore DECIMAL(8,6) NULL;
END
GO

IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.FaceVerificationAttempts')
      AND name = 'PayrollId'
      AND is_nullable = 0
)
BEGIN
    ALTER TABLE dbo.FaceVerificationAttempts ALTER COLUMN PayrollId INT NULL;
END
GO

IF OBJECT_ID('dbo.FK_TimeEntries_MobileDevices', 'F') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD CONSTRAINT FK_TimeEntries_MobileDevices FOREIGN KEY (SourceDeviceId) REFERENCES dbo.MobileDevices(MobileDeviceId);
END
GO

IF OBJECT_ID('dbo.FK_TimeEntries_FaceVerificationAttempts', 'F') IS NULL
BEGIN
    ALTER TABLE dbo.TimeEntries
    ADD CONSTRAINT FK_TimeEntries_FaceVerificationAttempts FOREIGN KEY (VerificationAttemptId) REFERENCES dbo.FaceVerificationAttempts(FaceVerificationAttemptId);
END
GO

CREATE OR ALTER VIEW dbo.vw_EmployeeFaceStatus
AS
SELECT
    E.PayrollId,
    LTRIM(RTRIM(CONCAT(E.FirstName, ' ', E.LastName))) AS FullName,
    CASE WHEN EXISTS
    (
        SELECT 1
        FROM dbo.FaceTemplates FT
        WHERE FT.PayrollId = E.PayrollId
          AND FT.IsActive = 1
    )
    THEN CAST(1 AS BIT)
    ELSE CAST(0 AS BIT)
    END AS HasActiveFaceTemplate
FROM dbo.Employees E;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RegisterMobileDevice
    @EmployeeId INT,
    @DeviceIdentifier NVARCHAR(150),
    @DeviceName NVARCHAR(150) = NULL,
    @Platform NVARCHAR(30) = 'Android'
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.MobileDevices WHERE DeviceIdentifier = @DeviceIdentifier)
    BEGIN
        UPDATE dbo.MobileDevices
        SET PayrollId = @EmployeeId,
            DeviceName = @DeviceName,
            Platform = @Platform,
            LastSeenAt = SYSUTCDATETIME()
        WHERE DeviceIdentifier = @DeviceIdentifier;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.MobileDevices (PayrollId, DeviceIdentifier, DeviceName, Platform, LastSeenAt)
        VALUES (@EmployeeId, @DeviceIdentifier, @DeviceName, @Platform, SYSUTCDATETIME());
    END

    SELECT TOP 1 *
    FROM dbo.MobileDevices
    WHERE DeviceIdentifier = @DeviceIdentifier;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SaveFaceTemplate
    @EmployeeId INT,
    @TemplateVersion NVARCHAR(30),
    @TemplateData VARBINARY(MAX),
    @EmbeddingJson NVARCHAR(MAX) = NULL,
    @EmbeddingDimensions INT = NULL,
    @ModelName NVARCHAR(50) = NULL,
    @DetectorBackend NVARCHAR(50) = NULL,
    @EnrolledByPayrollId INT = NULL,
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.FaceTemplates
    SET IsActive = 0
    WHERE PayrollId = @EmployeeId
      AND IsActive = 1;

    INSERT INTO dbo.FaceTemplates
    (
        PayrollId,
        ProviderName,
        TemplateVersion,
        TemplateData,
        EmbeddingJson,
        EmbeddingDimensions,
        ModelName,
        DetectorBackend,
        EnrolledByPayrollId,
        Notes
    )
    VALUES
    (
        @EmployeeId,
        'DeepFace',
        @TemplateVersion,
        @TemplateData,
        @EmbeddingJson,
        @EmbeddingDimensions,
        @ModelName,
        @DetectorBackend,
        @EnrolledByPayrollId,
        @Notes
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RecordFaceVerificationAttempt
    @EmployeeId INT,
    @DeviceIdentifier NVARCHAR(150),
    @VerificationPurpose NVARCHAR(30),
    @VerificationStatus NVARCHAR(20),
    @ConfidenceScore DECIMAL(5,4) = NULL,
    @LivenessScore DECIMAL(5,4) = NULL,
    @DistanceScore DECIMAL(8,6) = NULL,
    @FailureReason NVARCHAR(200) = NULL,
    @ProviderReference NVARCHAR(120) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MobileDeviceId INT;
    SELECT @MobileDeviceId = MobileDeviceId
    FROM dbo.MobileDevices
    WHERE DeviceIdentifier = @DeviceIdentifier;

    INSERT INTO dbo.FaceVerificationAttempts
    (
        PayrollId,
        MobileDeviceId,
        VerificationPurpose,
        VerificationStatus,
        ConfidenceScore,
        LivenessScore,
        DistanceScore,
        FailureReason,
        ProviderReference
    )
    VALUES
    (
        @EmployeeId,
        @MobileDeviceId,
        @VerificationPurpose,
        @VerificationStatus,
        @ConfidenceScore,
        @LivenessScore,
        @DistanceScore,
        @FailureReason,
        @ProviderReference
    );

    SELECT SCOPE_IDENTITY() AS FaceVerificationAttemptId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_MobileClockEvent
    @EmployeeId INT,
    @EventType NVARCHAR(20),
    @DeviceIdentifier NVARCHAR(150),
    @VerificationAttemptId INT,
    @Latitude DECIMAL(9,6) = NULL,
    @Longitude DECIMAL(9,6) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MobileDeviceId INT;
    SELECT @MobileDeviceId = MobileDeviceId
    FROM dbo.MobileDevices
    WHERE DeviceIdentifier = @DeviceIdentifier;

    IF @MobileDeviceId IS NULL
    BEGIN
        RAISERROR('Device is not registered.', 16, 1);
        RETURN;
    END

    IF @EventType = 'ClockIn'
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM dbo.TimeEntries
            WHERE PayrollId = @EmployeeId
              AND ClockOutTime IS NULL
        )
        BEGIN
            RAISERROR('Employee is already clocked in.', 16, 1);
            RETURN;
        END

        INSERT INTO dbo.TimeEntries
        (
            PayrollId,
            ClockInTime,
            ClockMethod,
            SourceDeviceId,
            VerificationAttemptId,
            Latitude,
            Longitude
        )
        VALUES
        (
            @EmployeeId,
            SYSDATETIME(),
            'AndroidFace',
            @MobileDeviceId,
            @VerificationAttemptId,
            @Latitude,
            @Longitude
        );
    END
    ELSE IF @EventType = 'ClockOut'
    BEGIN
        UPDATE TOP (1) dbo.TimeEntries
        SET ClockOutTime = SYSDATETIME(),
            ClockMethod = 'AndroidFace',
            SourceDeviceId = @MobileDeviceId,
            VerificationAttemptId = @VerificationAttemptId,
            Latitude = @Latitude,
            Longitude = @Longitude
        WHERE PayrollId = @EmployeeId
          AND ClockOutTime IS NULL;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Employee is not currently clocked in.', 16, 1);
            RETURN;
        END
    END
    ELSE
    BEGIN
        RAISERROR('Unsupported event type.', 16, 1);
        RETURN;
    END
END;
GO
