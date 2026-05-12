

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
