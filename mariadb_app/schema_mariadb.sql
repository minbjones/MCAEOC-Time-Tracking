CREATE DATABASE IF NOT EXISTS `dbo`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `dbo`;

CREATE TABLE IF NOT EXISTS `Roles` (
    `RoleId` INT NOT NULL AUTO_INCREMENT,
    `RoleName` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`RoleId`),
    UNIQUE KEY `UX_Roles_RoleName` (`RoleName`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Departments` (
    `DepartmentId` INT NOT NULL,
    `DepartmentName` VARCHAR(100) NOT NULL,
    PRIMARY KEY (`DepartmentId`),
    UNIQUE KEY `UX_Departments_Name` (`DepartmentName`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `Employees` (
    `EmployeeId` INT NOT NULL AUTO_INCREMENT,
    `PayrollId` VARCHAR(8) NOT NULL,
    `DepartmentId` INT NOT NULL,
    `FirstName` VARCHAR(75) NOT NULL,
    `LastName` VARCHAR(75) NOT NULL,
    `Email` VARCHAR(255) NOT NULL,
    `UserId` VARCHAR(150) NOT NULL,
    `PersonalLeave` TINYINT(1) NOT NULL DEFAULT 0,
    `ReportsToUserId` VARCHAR(150) NULL,
    `PasswordSalt` VARCHAR(32) NOT NULL,
    `PasswordHash` VARCHAR(64) NOT NULL,
    `MustChangePassword` TINYINT(1) NOT NULL DEFAULT 1,
    `RoleId` INT NOT NULL,
    `HireDate` DATE NOT NULL,
    `IsActive` ENUM('Yes', 'No') NOT NULL DEFAULT 'Yes',
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`EmployeeId`),
    UNIQUE KEY `UX_Employees_PayrollId` (`PayrollId`),
    UNIQUE KEY `UX_Employees_Email` (`Email`),
    UNIQUE KEY `UX_Employees_UserId` (`UserId`),
    KEY `IX_Employees_DepartmentId` (`DepartmentId`),
    KEY `IX_Employees_RoleId` (`RoleId`),
    KEY `IX_Employees_ReportsToUserId` (`ReportsToUserId`),
    CONSTRAINT `FK_Employees_Departments` FOREIGN KEY (`DepartmentId`) REFERENCES `Departments` (`DepartmentId`),
    CONSTRAINT `FK_Employees_Roles` FOREIGN KEY (`RoleId`) REFERENCES `Roles` (`RoleId`),
    CONSTRAINT `FK_Employees_ReportsToUserId` FOREIGN KEY (`ReportsToUserId`) REFERENCES `Employees` (`UserId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `TimeEntries` (
    `TimeEntryId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `ClockInTime` DATETIME(6) NOT NULL,
    `ClockOutTime` DATETIME(6) NULL,
    `Notes` VARCHAR(500) NULL,
    `EntrySource` VARCHAR(20) NOT NULL DEFAULT 'Clock',
    `ClockMethod` VARCHAR(30) NOT NULL DEFAULT 'WebManual',
    `SourceDeviceId` INT NULL,
    `VerificationAttemptId` INT NULL,
    `Latitude` DECIMAL(9,6) NULL,
    `Longitude` DECIMAL(9,6) NULL,
    `CreatedByEmployeeId` INT NULL,
    `LastModifiedAt` DATETIME(6) NULL,
    `LastModifiedByEmployeeId` INT NULL,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`TimeEntryId`),
    KEY `IX_TimeEntries_EmployeeId` (`EmployeeId`),
    CONSTRAINT `FK_TimeEntries_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_TimeEntries_CreatedByEmployee` FOREIGN KEY (`CreatedByEmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_TimeEntries_LastModifiedByEmployee` FOREIGN KEY (`LastModifiedByEmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `TimeEntryAudit` (
    `TimeEntryAuditId` INT NOT NULL AUTO_INCREMENT,
    `TimeEntryId` INT NOT NULL,
    `EmployeeId` INT NOT NULL,
    `ActionType` VARCHAR(30) NOT NULL,
    `ChangeReason` VARCHAR(500) NOT NULL,
    `OldClockInTime` DATETIME(6) NULL,
    `NewClockInTime` DATETIME(6) NULL,
    `OldClockOutTime` DATETIME(6) NULL,
    `NewClockOutTime` DATETIME(6) NULL,
    `OldNotes` VARCHAR(500) NULL,
    `NewNotes` VARCHAR(500) NULL,
    `OldEntrySource` VARCHAR(20) NULL,
    `NewEntrySource` VARCHAR(20) NULL,
    `ChangedByEmployeeId` INT NOT NULL,
    `ChangedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`TimeEntryAuditId`),
    KEY `IX_TimeEntryAudit_TimeEntryId` (`TimeEntryId`),
    CONSTRAINT `FK_TimeEntryAudit_TimeEntries` FOREIGN KEY (`TimeEntryId`) REFERENCES `TimeEntries` (`TimeEntryId`),
    CONSTRAINT `FK_TimeEntryAudit_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_TimeEntryAudit_ChangedBy` FOREIGN KEY (`ChangedByEmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `LeaveRequests` (
    `LeaveRequestId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `LeaveType` VARCHAR(20) NOT NULL,
    `StartDate` DATE NOT NULL,
    `EndDate` DATE NOT NULL,
    `RequestedHours` DECIMAL(8,2) NOT NULL,
    `ApprovalStatus` VARCHAR(20) NOT NULL DEFAULT 'Pending',
    `Notes` VARCHAR(500) NULL,
    `RequestedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `ApprovedByEmployeeId` INT NULL,
    `ApprovedAt` DATETIME(6) NULL,
    PRIMARY KEY (`LeaveRequestId`),
    KEY `IX_LeaveRequests_EmployeeId` (`EmployeeId`),
    CONSTRAINT `FK_LeaveRequests_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_LeaveRequests_Approvers` FOREIGN KEY (`ApprovedByEmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `LeaveLedger` (
    `LeaveLedgerId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `EntryDate` DATE NOT NULL,
    `LeaveType` VARCHAR(20) NOT NULL,
    `Hours` DECIMAL(8,2) NOT NULL,
    `EntryReason` VARCHAR(30) NOT NULL,
    `ReferenceId` INT NULL,
    `Notes` VARCHAR(500) NULL,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`LeaveLedgerId`),
    KEY `IX_LeaveLedger_EmployeeId` (`EmployeeId`),
    CONSTRAINT `FK_LeaveLedger_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `MobileDevices` (
    `MobileDeviceId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `DeviceIdentifier` VARCHAR(200) NOT NULL,
    `DeviceName` VARCHAR(200) NULL,
    `Platform` VARCHAR(30) NOT NULL DEFAULT 'Android',
    `IsTrusted` TINYINT(1) NOT NULL DEFAULT 1,
    `RegisteredAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `LastSeenAt` DATETIME(6) NULL,
    `IsActive` TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`MobileDeviceId`),
    UNIQUE KEY `UX_MobileDevices_DeviceIdentifier` (`DeviceIdentifier`),
    KEY `IX_MobileDevices_EmployeeId` (`EmployeeId`),
    CONSTRAINT `FK_MobileDevices_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `EmployeeDeviceMappings` (
    `EmployeeDeviceMappingId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `SystemName` VARCHAR(50) NOT NULL,
    `ExternalUserId` VARCHAR(100) NOT NULL,
    `ExternalUserName` VARCHAR(200) NULL,
    `DeviceIdentifier` VARCHAR(200) NULL,
    `Notes` VARCHAR(500) NULL,
    `IsActive` TINYINT(1) NOT NULL DEFAULT 1,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `UpdatedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`EmployeeDeviceMappingId`),
    UNIQUE KEY `UX_EmployeeDeviceMappings_System_ExternalUserId` (`SystemName`, `ExternalUserId`),
    KEY `IX_EmployeeDeviceMappings_EmployeeId` (`EmployeeId`),
    KEY `IX_EmployeeDeviceMappings_DeviceIdentifier` (`DeviceIdentifier`),
    CONSTRAINT `FK_EmployeeDeviceMappings_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `DevicePunchImports` (
    `DevicePunchImportId` INT NOT NULL AUTO_INCREMENT,
    `SystemName` VARCHAR(50) NOT NULL,
    `DeviceIdentifier` VARCHAR(200) NOT NULL,
    `ExternalUserId` VARCHAR(100) NOT NULL,
    `ExternalUserName` VARCHAR(200) NULL,
    `PunchTimestamp` DATETIME(6) NOT NULL,
    `PunchDirection` VARCHAR(20) NULL,
    `ImportStatus` VARCHAR(20) NOT NULL DEFAULT 'Pending',
    `FailureReason` VARCHAR(500) NULL,
    `RawPayloadJson` LONGTEXT NULL,
    `EmployeeId` INT NULL,
    `CreatedTimeEntryId` INT NULL,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`DevicePunchImportId`),
    UNIQUE KEY `UX_DevicePunchImports_SourcePunch` (`SystemName`, `DeviceIdentifier`, `ExternalUserId`, `PunchTimestamp`),
    KEY `IX_DevicePunchImports_EmployeeId` (`EmployeeId`),
    KEY `IX_DevicePunchImports_CreatedTimeEntryId` (`CreatedTimeEntryId`),
    KEY `IX_DevicePunchImports_Status` (`ImportStatus`),
    CONSTRAINT `FK_DevicePunchImports_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_DevicePunchImports_TimeEntries` FOREIGN KEY (`CreatedTimeEntryId`) REFERENCES `TimeEntries` (`TimeEntryId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `FaceTemplates` (
    `FaceTemplateId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `ProviderName` VARCHAR(50) NOT NULL DEFAULT 'DeepFace',
    `ProviderPersonGroupId` VARCHAR(64) NULL,
    `ProviderPersonId` VARCHAR(64) NULL,
    `ProviderPersistedFaceId` VARCHAR(64) NULL,
    `ModelName` VARCHAR(50) NOT NULL,
    `DetectorBackend` VARCHAR(50) NOT NULL,
    `TemplateVersion` VARCHAR(50) NOT NULL,
    `TemplateData` LONGBLOB NULL,
    `EmbeddingJson` LONGTEXT NOT NULL,
    `EmbeddingDimensions` INT NOT NULL,
    `EncryptionKeyLabel` VARCHAR(100) NULL,
    `EnrolledAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `EnrolledByEmployeeId` INT NULL,
    `IsActive` TINYINT(1) NOT NULL DEFAULT 1,
    `Notes` VARCHAR(500) NULL,
    PRIMARY KEY (`FaceTemplateId`),
    KEY `IX_FaceTemplates_EmployeeId` (`EmployeeId`),
    KEY `IX_FaceTemplates_EnrolledByEmployeeId` (`EnrolledByEmployeeId`),
    CONSTRAINT `FK_FaceTemplates_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_FaceTemplates_EnrolledBy` FOREIGN KEY (`EnrolledByEmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `FaceVerificationAttempts` (
    `FaceVerificationAttemptId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NULL,
    `MobileDeviceId` INT NULL,
    `DeviceIdentifier` VARCHAR(200) NOT NULL,
    `VerificationPurpose` VARCHAR(30) NOT NULL,
    `VerificationStatus` VARCHAR(20) NOT NULL,
    `ConfidenceScore` DECIMAL(8,4) NULL,
    `LivenessScore` DECIMAL(8,4) NULL,
    `DistanceScore` DECIMAL(8,6) NULL,
    `FailureReason` VARCHAR(500) NULL,
    `CapturedAt` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `ProviderReference` VARCHAR(120) NULL,
    PRIMARY KEY (`FaceVerificationAttemptId`),
    KEY `IX_FaceVerificationAttempts_EmployeeId` (`EmployeeId`),
    KEY `IX_FaceVerificationAttempts_MobileDeviceId` (`MobileDeviceId`),
    CONSTRAINT `FK_FaceVerificationAttempts_Employees` FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_FaceVerificationAttempts_MobileDevices` FOREIGN KEY (`MobileDeviceId`) REFERENCES `MobileDevices` (`MobileDeviceId`)
) ENGINE=InnoDB;

SET @sql = IF (
    EXISTS (
        SELECT 1
        FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'TimeEntries'
          AND CONSTRAINT_NAME = 'FK_TimeEntries_MobileDevices'
    ),
    'SELECT 1',
    'ALTER TABLE `TimeEntries` ADD CONSTRAINT `FK_TimeEntries_MobileDevices` FOREIGN KEY (`SourceDeviceId`) REFERENCES `MobileDevices` (`MobileDeviceId`)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF (
    EXISTS (
        SELECT 1
        FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'TimeEntries'
          AND CONSTRAINT_NAME = 'FK_TimeEntries_FaceVerificationAttempts'
    ),
    'SELECT 1',
    'ALTER TABLE `TimeEntries` ADD CONSTRAINT `FK_TimeEntries_FaceVerificationAttempts` FOREIGN KEY (`VerificationAttemptId`) REFERENCES `FaceVerificationAttempts` (`FaceVerificationAttemptId`)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DELIMITER $$

CREATE FUNCTION `fn_GetMonthlyAccrualHours`(p_HireDate DATE)
RETURNS DECIMAL(8,2)
DETERMINISTIC
BEGIN
    DECLARE v_YearsEmployed INT;
    SET v_YearsEmployed = TIMESTAMPDIFF(YEAR, p_HireDate, CURDATE());

    IF DATE_ADD(p_HireDate, INTERVAL v_YearsEmployed YEAR) > CURDATE() THEN
        SET v_YearsEmployed = v_YearsEmployed - 1;
    END IF;

    RETURN CASE
        WHEN v_YearsEmployed < 3 THEN 10.00
        WHEN v_YearsEmployed < 5 THEN 12.00
        ELSE 14.00
    END;
END$$

CREATE PROCEDURE `usp_ClockIn`(IN p_EmployeeId INT)
BEGIN
    IF EXISTS (
        SELECT 1 FROM `TimeEntries`
        WHERE `EmployeeId` = p_EmployeeId
          AND `ClockOutTime` IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Employee is already clocked in.';
    END IF;

    INSERT INTO `TimeEntries` (`EmployeeId`, `ClockInTime`)
    VALUES (p_EmployeeId, UTC_TIMESTAMP(6));
END$$

CREATE PROCEDURE `usp_ClockOut`(IN p_EmployeeId INT)
BEGIN
    DECLARE v_TimeEntryId INT;

    SELECT `TimeEntryId`
      INTO v_TimeEntryId
    FROM `TimeEntries`
    WHERE `EmployeeId` = p_EmployeeId
      AND `ClockOutTime` IS NULL
    ORDER BY `ClockInTime` DESC, `TimeEntryId` DESC
    LIMIT 1;

    IF v_TimeEntryId IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Employee is not currently clocked in.';
    END IF;

    UPDATE `TimeEntries`
    SET `ClockOutTime` = UTC_TIMESTAMP(6)
    WHERE `TimeEntryId` = v_TimeEntryId;
END$$

CREATE PROCEDURE `usp_RequestLeave`(
    IN p_EmployeeId INT,
    IN p_LeaveType VARCHAR(20),
    IN p_StartDate DATE,
    IN p_EndDate DATE,
    IN p_RequestedHours DECIMAL(8,2),
    IN p_Notes VARCHAR(500)
)
BEGIN
    DECLARE v_PersonalLeave TINYINT(1);
    SELECT `PersonalLeave` INTO v_PersonalLeave FROM `Employees` WHERE `EmployeeId` = p_EmployeeId LIMIT 1;

    IF p_EndDate < p_StartDate THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'End date cannot be earlier than start date.';
    END IF;

    IF v_PersonalLeave = 1 AND p_LeaveType = 'Annual' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Personal-leave employees accrue Personal leave instead of Annual leave.';
    END IF;

    IF IFNULL(v_PersonalLeave, 0) = 0 AND p_LeaveType = 'Personal' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only personal-leave employees can request Personal leave.';
    END IF;

    INSERT INTO `LeaveRequests` (`EmployeeId`, `LeaveType`, `StartDate`, `EndDate`, `RequestedHours`, `Notes`)
    VALUES (p_EmployeeId, p_LeaveType, p_StartDate, p_EndDate, p_RequestedHours, p_Notes);
END$$

CREATE PROCEDURE `usp_CancelLeaveRequest`(IN p_LeaveRequestId INT, IN p_EmployeeId INT)
BEGIN
    UPDATE `LeaveRequests`
    SET `ApprovalStatus` = 'Canceled',
        `ApprovedByEmployeeId` = p_EmployeeId,
        `ApprovedAt` = UTC_TIMESTAMP(6),
        `Notes` = CONCAT(COALESCE(`Notes`, ''), IF(`Notes` IS NULL OR `Notes` = '', '', ' | '), 'Canceled by employee')
    WHERE `LeaveRequestId` = p_LeaveRequestId
      AND `EmployeeId` = p_EmployeeId
      AND `ApprovalStatus` = 'Pending';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only pending leave requests can be cancelled by the requesting employee.';
    END IF;
END$$

CREATE PROCEDURE `usp_ProcessLeaveRequest`(
    IN p_LeaveRequestId INT,
    IN p_ApprovalStatus VARCHAR(20),
    IN p_ApprovedByEmployeeId INT
)
BEGIN
    DECLARE v_EmployeeId INT;
    DECLARE v_LeaveType VARCHAR(20);
    DECLARE v_RequestedHours DECIMAL(8,2);
    DECLARE v_CurrentBalance DECIMAL(8,2);

    SELECT `EmployeeId`, `LeaveType`, `RequestedHours`
      INTO v_EmployeeId, v_LeaveType, v_RequestedHours
    FROM `LeaveRequests`
    WHERE `LeaveRequestId` = p_LeaveRequestId
      AND `ApprovalStatus` = 'Pending'
    LIMIT 1;

    IF v_EmployeeId IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Leave request was not found or is already processed.';
    END IF;

    IF p_ApprovalStatus = 'Approved' THEN
        SELECT CASE
            WHEN v_LeaveType = 'Annual' THEN `AnnualLeaveHours`
            WHEN v_LeaveType = 'Personal' THEN `PersonalLeaveHours`
            ELSE `SickLeaveHours`
        END
        INTO v_CurrentBalance
        FROM `vw_EmployeeLeaveBalances`
        WHERE `EmployeeId` = v_EmployeeId
        LIMIT 1;

        IF IFNULL(v_CurrentBalance, 0) < v_RequestedHours THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient leave balance.';
        END IF;

        INSERT INTO `LeaveLedger` (`EmployeeId`, `EntryDate`, `LeaveType`, `Hours`, `EntryReason`, `ReferenceId`, `Notes`)
        VALUES (v_EmployeeId, UTC_DATE(), v_LeaveType, v_RequestedHours * -1, 'Usage', p_LeaveRequestId, 'Approved leave request');
    END IF;

    UPDATE `LeaveRequests`
    SET `ApprovalStatus` = p_ApprovalStatus,
        `ApprovedByEmployeeId` = p_ApprovedByEmployeeId,
        `ApprovedAt` = UTC_TIMESTAMP(6)
    WHERE `LeaveRequestId` = p_LeaveRequestId;
END$$

CREATE PROCEDURE `usp_ResetEmployeePassword`(
    IN p_EmployeeId INT,
    IN p_PasswordSalt VARCHAR(32),
    IN p_PasswordHash VARCHAR(64)
)
BEGIN
    UPDATE `Employees`
    SET `PasswordSalt` = p_PasswordSalt,
        `PasswordHash` = p_PasswordHash,
        `MustChangePassword` = 1
    WHERE `EmployeeId` = p_EmployeeId;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Employee not found.';
    END IF;
END$$

CREATE PROCEDURE `usp_RegisterMobileDevice`(
    IN p_EmployeeId INT,
    IN p_DeviceIdentifier VARCHAR(200),
    IN p_DeviceName VARCHAR(200),
    IN p_Platform VARCHAR(30)
)
BEGIN
    DECLARE v_MobileDeviceId INT;

    SELECT `MobileDeviceId`
      INTO v_MobileDeviceId
    FROM `MobileDevices`
    WHERE `DeviceIdentifier` = p_DeviceIdentifier
    LIMIT 1;

    IF v_MobileDeviceId IS NULL THEN
        INSERT INTO `MobileDevices`
        (
            `EmployeeId`,
            `DeviceIdentifier`,
            `DeviceName`,
            `Platform`,
            `LastSeenAt`,
            `IsTrusted`,
            `IsActive`
        )
        VALUES
        (
            p_EmployeeId,
            p_DeviceIdentifier,
            p_DeviceName,
            COALESCE(p_Platform, 'Android'),
            UTC_TIMESTAMP(6),
            1,
            1
        );

        SET v_MobileDeviceId = LAST_INSERT_ID();
    ELSE
        UPDATE `MobileDevices`
        SET `EmployeeId` = p_EmployeeId,
            `DeviceName` = p_DeviceName,
            `Platform` = COALESCE(p_Platform, `Platform`),
            `LastSeenAt` = UTC_TIMESTAMP(6),
            `IsTrusted` = 1,
            `IsActive` = 1
        WHERE `MobileDeviceId` = v_MobileDeviceId;
    END IF;

    SELECT *
    FROM `MobileDevices`
    WHERE `MobileDeviceId` = v_MobileDeviceId;
END$$

CREATE PROCEDURE `usp_SaveFaceTemplate`(
    IN p_EmployeeId INT,
    IN p_TemplateVersion VARCHAR(50),
    IN p_TemplateData LONGBLOB,
    IN p_EmbeddingJson LONGTEXT,
    IN p_EmbeddingDimensions INT,
    IN p_ModelName VARCHAR(50),
    IN p_DetectorBackend VARCHAR(50),
    IN p_EnrolledByEmployeeId INT,
    IN p_Notes VARCHAR(500)
)
BEGIN
    UPDATE `FaceTemplates`
    SET `IsActive` = 0
    WHERE `EmployeeId` = p_EmployeeId
      AND `IsActive` = 1;

    INSERT INTO `FaceTemplates`
    (
        `EmployeeId`,
        `ProviderName`,
        `ModelName`,
        `DetectorBackend`,
        `TemplateVersion`,
        `TemplateData`,
        `EmbeddingJson`,
        `EmbeddingDimensions`,
        `EnrolledByEmployeeId`,
        `Notes`
    )
    VALUES
    (
        p_EmployeeId,
        'DeepFace',
        p_ModelName,
        p_DetectorBackend,
        p_TemplateVersion,
        p_TemplateData,
        p_EmbeddingJson,
        p_EmbeddingDimensions,
        p_EnrolledByEmployeeId,
        p_Notes
    );

    SELECT LAST_INSERT_ID() AS `FaceTemplateId`;
END$$

CREATE PROCEDURE `usp_RecordFaceVerificationAttempt`(
    IN p_EmployeeId INT,
    IN p_DeviceIdentifier VARCHAR(200),
    IN p_VerificationPurpose VARCHAR(30),
    IN p_VerificationStatus VARCHAR(20),
    IN p_ConfidenceScore DECIMAL(8,4),
    IN p_LivenessScore DECIMAL(8,4),
    IN p_DistanceScore DECIMAL(8,6),
    IN p_FailureReason VARCHAR(500),
    IN p_ProviderReference VARCHAR(120)
)
BEGIN
    DECLARE v_MobileDeviceId INT;

    SELECT `MobileDeviceId`
      INTO v_MobileDeviceId
    FROM `MobileDevices`
    WHERE `DeviceIdentifier` = p_DeviceIdentifier
    LIMIT 1;

    INSERT INTO `FaceVerificationAttempts`
    (
        `EmployeeId`,
        `MobileDeviceId`,
        `DeviceIdentifier`,
        `VerificationPurpose`,
        `VerificationStatus`,
        `ConfidenceScore`,
        `LivenessScore`,
        `DistanceScore`,
        `FailureReason`,
        `ProviderReference`
    )
    VALUES
    (
        p_EmployeeId,
        v_MobileDeviceId,
        p_DeviceIdentifier,
        p_VerificationPurpose,
        p_VerificationStatus,
        p_ConfidenceScore,
        p_LivenessScore,
        p_DistanceScore,
        p_FailureReason,
        p_ProviderReference
    );

    SELECT LAST_INSERT_ID() AS `FaceVerificationAttemptId`;
END$$

CREATE PROCEDURE `usp_MobileClockEvent`(
    IN p_EmployeeId INT,
    IN p_EventType VARCHAR(20),
    IN p_DeviceIdentifier VARCHAR(200),
    IN p_VerificationAttemptId INT,
    IN p_Latitude DECIMAL(9,6),
    IN p_Longitude DECIMAL(9,6)
)
BEGIN
    DECLARE v_MobileDeviceId INT;
    DECLARE v_OpenTimeEntryId INT;
    DECLARE v_LocationNote VARCHAR(500);

    SELECT `MobileDeviceId`
      INTO v_MobileDeviceId
    FROM `MobileDevices`
    WHERE `DeviceIdentifier` = p_DeviceIdentifier
      AND `IsActive` = 1
    LIMIT 1;

    IF v_MobileDeviceId IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Device is not registered.';
    END IF;

    IF p_Latitude IS NOT NULL AND p_Longitude IS NOT NULL THEN
        SET v_LocationNote = CONCAT('Lat ', p_Latitude, ', Lon ', p_Longitude);
    ELSE
        SET v_LocationNote = NULL;
    END IF;

    IF p_EventType = 'ClockIn' THEN
        IF EXISTS (
            SELECT 1
            FROM `TimeEntries`
            WHERE `EmployeeId` = p_EmployeeId
              AND `ClockOutTime` IS NULL
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Employee is already clocked in.';
        END IF;

        INSERT INTO `TimeEntries`
        (
            `EmployeeId`,
            `ClockInTime`,
            `Notes`,
            `EntrySource`,
            `ClockMethod`,
            `SourceDeviceId`,
            `VerificationAttemptId`,
            `Latitude`,
            `Longitude`
        )
        VALUES
        (
            p_EmployeeId,
            UTC_TIMESTAMP(6),
            COALESCE(v_LocationNote, CONCAT('Mobile clock-in from ', p_DeviceIdentifier)),
            'Mobile',
            'AndroidFace',
            v_MobileDeviceId,
            p_VerificationAttemptId,
            p_Latitude,
            p_Longitude
        );
    ELSEIF p_EventType = 'ClockOut' THEN
        SELECT `TimeEntryId`
          INTO v_OpenTimeEntryId
        FROM `TimeEntries`
        WHERE `EmployeeId` = p_EmployeeId
          AND `ClockOutTime` IS NULL
        ORDER BY `ClockInTime` DESC, `TimeEntryId` DESC
        LIMIT 1;

        IF v_OpenTimeEntryId IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Employee is not currently clocked in.';
        END IF;

        UPDATE `TimeEntries`
        SET `ClockOutTime` = UTC_TIMESTAMP(6),
            `Notes` = COALESCE(`Notes`, COALESCE(v_LocationNote, CONCAT('Mobile clock-out from ', p_DeviceIdentifier))),
            `ClockMethod` = 'AndroidFace',
            `SourceDeviceId` = v_MobileDeviceId,
            `VerificationAttemptId` = p_VerificationAttemptId,
            `Latitude` = COALESCE(p_Latitude, `Latitude`),
            `Longitude` = COALESCE(p_Longitude, `Longitude`)
        WHERE `TimeEntryId` = v_OpenTimeEntryId;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unsupported mobile clock event.';
    END IF;
END$$

CREATE PROCEDURE `usp_SaveEmployeeDeviceMapping`(
    IN p_EmployeeId INT,
    IN p_SystemName VARCHAR(50),
    IN p_ExternalUserId VARCHAR(100),
    IN p_ExternalUserName VARCHAR(200),
    IN p_DeviceIdentifier VARCHAR(200),
    IN p_Notes VARCHAR(500),
    IN p_IsActive TINYINT(1)
)
BEGIN
    DECLARE v_ExistingMappingId INT;

    SELECT `EmployeeDeviceMappingId`
      INTO v_ExistingMappingId
    FROM `EmployeeDeviceMappings`
    WHERE `SystemName` = p_SystemName
      AND `ExternalUserId` = p_ExternalUserId
    LIMIT 1;

    IF v_ExistingMappingId IS NULL THEN
        INSERT INTO `EmployeeDeviceMappings`
        (
            `EmployeeId`,
            `SystemName`,
            `ExternalUserId`,
            `ExternalUserName`,
            `DeviceIdentifier`,
            `Notes`,
            `IsActive`
        )
        VALUES
        (
            p_EmployeeId,
            p_SystemName,
            p_ExternalUserId,
            p_ExternalUserName,
            p_DeviceIdentifier,
            p_Notes,
            COALESCE(p_IsActive, 1)
        );

        SET v_ExistingMappingId = LAST_INSERT_ID();
    ELSE
        UPDATE `EmployeeDeviceMappings`
        SET `EmployeeId` = p_EmployeeId,
            `ExternalUserName` = p_ExternalUserName,
            `DeviceIdentifier` = p_DeviceIdentifier,
            `Notes` = p_Notes,
            `IsActive` = COALESCE(p_IsActive, `IsActive`)
        WHERE `EmployeeDeviceMappingId` = v_ExistingMappingId;
    END IF;

    SELECT *
    FROM `EmployeeDeviceMappings`
    WHERE `EmployeeDeviceMappingId` = v_ExistingMappingId;
END$$

CREATE PROCEDURE `usp_ImportDevicePunch`(
    IN p_SystemName VARCHAR(50),
    IN p_DeviceIdentifier VARCHAR(200),
    IN p_ExternalUserId VARCHAR(100),
    IN p_ExternalUserName VARCHAR(200),
    IN p_PunchTimestamp DATETIME(6),
    IN p_PunchDirection VARCHAR(20),
    IN p_RawPayloadJson LONGTEXT
)
BEGIN
    DECLARE v_EmployeeId INT;
    DECLARE v_DevicePunchImportId INT;
    DECLARE v_OpenTimeEntryId INT;
    DECLARE v_CreatedTimeEntryId INT;
    DECLARE v_EventType VARCHAR(20);
    DECLARE v_Notes VARCHAR(500);

    IF EXISTS (
        SELECT 1
        FROM `DevicePunchImports`
        WHERE `SystemName` = p_SystemName
          AND `DeviceIdentifier` = p_DeviceIdentifier
          AND `ExternalUserId` = p_ExternalUserId
          AND `PunchTimestamp` = p_PunchTimestamp
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate device punch import.';
    END IF;

    SELECT `EmployeeId`
      INTO v_EmployeeId
    FROM `EmployeeDeviceMappings`
    WHERE `SystemName` = p_SystemName
      AND `ExternalUserId` = p_ExternalUserId
      AND `IsActive` = 1
    LIMIT 1;

    INSERT INTO `DevicePunchImports`
    (
        `SystemName`,
        `DeviceIdentifier`,
        `ExternalUserId`,
        `ExternalUserName`,
        `PunchTimestamp`,
        `PunchDirection`,
        `ImportStatus`,
        `FailureReason`,
        `RawPayloadJson`,
        `EmployeeId`
    )
    VALUES
    (
        p_SystemName,
        p_DeviceIdentifier,
        p_ExternalUserId,
        p_ExternalUserName,
        p_PunchTimestamp,
        p_PunchDirection,
        CASE WHEN v_EmployeeId IS NULL THEN 'Failed' ELSE 'Pending' END,
        CASE WHEN v_EmployeeId IS NULL THEN 'No employee mapping found.' ELSE NULL END,
        p_RawPayloadJson,
        v_EmployeeId
    );

    SET v_DevicePunchImportId = LAST_INSERT_ID();

    IF v_EmployeeId IS NULL THEN
        SELECT *
        FROM `DevicePunchImports`
        WHERE `DevicePunchImportId` = v_DevicePunchImportId;
    ELSE
        SELECT `TimeEntryId`
          INTO v_OpenTimeEntryId
        FROM `TimeEntries`
        WHERE `EmployeeId` = v_EmployeeId
          AND `ClockOutTime` IS NULL
        ORDER BY `ClockInTime` DESC, `TimeEntryId` DESC
        LIMIT 1;

        SET v_Notes = CONCAT('Imported from ', p_SystemName, ' (', p_DeviceIdentifier, ')');

        IF v_OpenTimeEntryId IS NULL THEN
            SET v_EventType = 'ClockIn';
            INSERT INTO `TimeEntries`
            (
                `EmployeeId`,
                `ClockInTime`,
                `Notes`,
                `EntrySource`,
                `ClockMethod`
            )
            VALUES
            (
                v_EmployeeId,
                p_PunchTimestamp,
                v_Notes,
                'Device',
                p_SystemName
            );
            SET v_CreatedTimeEntryId = LAST_INSERT_ID();
        ELSE
            SET v_EventType = 'ClockOut';
            UPDATE `TimeEntries`
            SET `ClockOutTime` = p_PunchTimestamp,
                `Notes` = COALESCE(`Notes`, v_Notes),
                `EntrySource` = COALESCE(`EntrySource`, 'Device'),
                `ClockMethod` = COALESCE(`ClockMethod`, p_SystemName)
            WHERE `TimeEntryId` = v_OpenTimeEntryId;
            SET v_CreatedTimeEntryId = v_OpenTimeEntryId;
        END IF;

        UPDATE `DevicePunchImports`
        SET `ImportStatus` = 'Imported',
            `FailureReason` = NULL,
            `CreatedTimeEntryId` = v_CreatedTimeEntryId,
            `PunchDirection` = COALESCE(p_PunchDirection, v_EventType)
        WHERE `DevicePunchImportId` = v_DevicePunchImportId;

        SELECT *
        FROM `DevicePunchImports`
        WHERE `DevicePunchImportId` = v_DevicePunchImportId;
    END IF;
END$$

CREATE PROCEDURE `usp_GetBiWeeklyTimesheet`(
    IN p_EmployeeId INT,
    IN p_PeriodStartDate DATE
)
BEGIN
    DECLARE v_PeriodEndDate DATE;
    SET v_PeriodEndDate = DATE_ADD(p_PeriodStartDate, INTERVAL 13 DAY);

    SELECT
        `TimeEntryId`,
        DATE(`ClockInTime`) AS `WorkDate`,
        `ClockInTime`,
        `ClockOutTime`,
        `Notes`,
        `EntrySource`,
        CAST(CASE WHEN `ClockOutTime` IS NULL THEN 0 ELSE TIMESTAMPDIFF(MINUTE, `ClockInTime`, `ClockOutTime`) / 60.0 END AS DECIMAL(8,2)) AS `WorkedHours`
    FROM `TimeEntries`
    WHERE `EmployeeId` = p_EmployeeId
      AND DATE(`ClockInTime`) BETWEEN p_PeriodStartDate AND v_PeriodEndDate
    ORDER BY `ClockInTime`;
END$$

CREATE PROCEDURE `usp_CreateEmployee`(
    IN p_FirstName VARCHAR(75),
    IN p_LastName VARCHAR(75),
    IN p_Email VARCHAR(255),
    IN p_UserId VARCHAR(150),
    IN p_RoleName VARCHAR(50),
    IN p_DepartmentId INT,
    IN p_PersonalLeave TINYINT(1),
    IN p_ReportsToUserId VARCHAR(150),
    IN p_HireDate DATE,
    IN p_PasswordSalt VARCHAR(32),
    IN p_PasswordHash VARCHAR(64)
)
BEGIN
    DECLARE v_RoleId INT;
    DECLARE v_DepartmentPrefix VARCHAR(2);
    DECLARE v_NextSequence INT;
    DECLARE v_PayrollId VARCHAR(8);

    SELECT `RoleId` INTO v_RoleId FROM `Roles` WHERE `RoleName` = p_RoleName LIMIT 1;
    IF v_RoleId IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid role name.';
    END IF;

    SET v_DepartmentPrefix = RIGHT(CONCAT('0', CAST(p_DepartmentId AS CHAR)), 2);
    SELECT IFNULL(MAX(CAST(RIGHT(`PayrollId`, 6) AS UNSIGNED)), 0) + 1
      INTO v_NextSequence
    FROM `Employees`
    WHERE `DepartmentId` = p_DepartmentId
      AND `PayrollId` LIKE CONCAT(v_DepartmentPrefix, '%');

    SET v_PayrollId = CONCAT(v_DepartmentPrefix, LPAD(v_NextSequence, 6, '0'));

    INSERT INTO `Employees`
    (
        `PayrollId`, `DepartmentId`, `FirstName`, `LastName`, `Email`, `UserId`, `PersonalLeave`, `ReportsToUserId`,
        `PasswordSalt`, `PasswordHash`, `MustChangePassword`, `RoleId`, `HireDate`, `IsActive`
    )
    VALUES
    (
        v_PayrollId, p_DepartmentId, p_FirstName, p_LastName, p_Email, p_UserId, p_PersonalLeave, p_ReportsToUserId,
        p_PasswordSalt, p_PasswordHash, 1, v_RoleId, p_HireDate, 'Yes'
    );

    SELECT LAST_INSERT_ID() AS `EmployeeId`, v_PayrollId AS `PayrollId`;
END$$

CREATE PROCEDURE `usp_UpdateEmployee`(
    IN p_EmployeeId INT,
    IN p_FirstName VARCHAR(75),
    IN p_LastName VARCHAR(75),
    IN p_Email VARCHAR(255),
    IN p_UserId VARCHAR(150),
    IN p_RoleName VARCHAR(50),
    IN p_DepartmentId INT,
    IN p_PersonalLeave TINYINT(1),
    IN p_ReportsToUserId VARCHAR(150),
    IN p_HireDate DATE,
    IN p_IsActive VARCHAR(3)
)
BEGIN
    DECLARE v_RoleId INT;
    SELECT `RoleId` INTO v_RoleId FROM `Roles` WHERE `RoleName` = p_RoleName LIMIT 1;
    IF v_RoleId IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid role name.';
    END IF;

    UPDATE `Employees`
    SET `FirstName` = p_FirstName,
        `LastName` = p_LastName,
        `Email` = p_Email,
        `UserId` = p_UserId,
        `DepartmentId` = p_DepartmentId,
        `PersonalLeave` = p_PersonalLeave,
        `ReportsToUserId` = p_ReportsToUserId,
        `RoleId` = v_RoleId,
        `HireDate` = p_HireDate,
        `IsActive` = p_IsActive
    WHERE `EmployeeId` = p_EmployeeId;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Employee not found.';
    END IF;
END$$

DELIMITER ;

CREATE OR REPLACE VIEW `vw_EmployeeLeaveBalances` AS
SELECT
    E.`EmployeeId`,
    SUM(CASE WHEN L.`LeaveType` = 'Annual' THEN L.`Hours` ELSE 0 END) AS `AnnualLeaveHours`,
    SUM(CASE WHEN L.`LeaveType` = 'Sick' THEN L.`Hours` ELSE 0 END) AS `SickLeaveHours`,
    SUM(CASE WHEN L.`LeaveType` = 'Personal' THEN L.`Hours` ELSE 0 END) AS `PersonalLeaveHours`
FROM `Employees` E
LEFT JOIN `LeaveLedger` L ON L.`EmployeeId` = E.`EmployeeId`
GROUP BY E.`EmployeeId`;

CREATE OR REPLACE VIEW `vw_EmployeeFaceStatus` AS
SELECT
    E.`EmployeeId`,
    E.`PayrollId`,
    LTRIM(RTRIM(CONCAT(E.`FirstName`, ' ', E.`LastName`))) AS `FullName`,
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM `FaceTemplates` FT
            WHERE FT.`EmployeeId` = E.`EmployeeId`
              AND FT.`IsActive` = 1
        ) THEN 1
        ELSE 0
    END AS `HasActiveFaceTemplate`
FROM `Employees` E;

INSERT IGNORE INTO `Roles` (`RoleName`)
VALUES ('Owner'), ('Executive Director'), ('Director'), ('Manager'), ('User'), ('Leave Manager');

INSERT IGNORE INTO `Departments` (`DepartmentId`, `DepartmentName`)
VALUES
    (20, 'Head Start-2'),
    (21, 'ADMIN'),
    (22, 'Head Start'),
    (24, 'ABC'),
    (44, 'CSBG'),
    (50, 'HIPPY'),
    (51, 'HEAP/LIHEAP'),
    (99, 'FINANCE');

INSERT IGNORE INTO `Employees`
(
    `PayrollId`, `DepartmentId`, `FirstName`, `LastName`, `Email`, `UserId`, `PersonalLeave`, `ReportsToUserId`,
    `PasswordSalt`, `PasswordHash`, `MustChangePassword`, `RoleId`, `HireDate`, `IsActive`
)
VALUES
(
    '99000001',
    99,
    'Admin',
    'User',
    'admin@mcaeoc.org',
    'admin',
    0,
    NULL,
    '14002008BLANTON1',
    '7375A6565E6182969595C2F73146280E6DF6155BEBCDB4DDCE2A1F01944FE91A',
    0,
    (SELECT `RoleId` FROM `Roles` WHERE `RoleName` = 'Owner' LIMIT 1),
    '2015-07-01',
    'Yes'
);
