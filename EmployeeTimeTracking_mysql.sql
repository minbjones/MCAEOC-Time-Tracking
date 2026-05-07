DROP DATABASE IF EXISTS `EmployeeTimeTracking`;
CREATE DATABASE `EmployeeTimeTracking`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `EmployeeTimeTracking`;

CREATE TABLE `Roles` (
    `RoleId` INT NOT NULL AUTO_INCREMENT,
    `RoleName` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`RoleId`),
    UNIQUE KEY `UX_Roles_RoleName` (`RoleName`)
) ENGINE=InnoDB;

CREATE TABLE `Employees` (
    `EmployeeId` INT NOT NULL AUTO_INCREMENT,
    `FullName` VARCHAR(150) NOT NULL,
    `Username` VARCHAR(60) NOT NULL,
    `IsHeadStart` TINYINT(1) NOT NULL DEFAULT 0,
    `ReportsToEmployeeId` INT NULL,
    `PasswordSalt` VARCHAR(32) NOT NULL,
    `PasswordHash` VARCHAR(64) NOT NULL,
    `MustChangePassword` TINYINT(1) NOT NULL DEFAULT 1,
    `RoleId` INT NOT NULL,
    `HireDate` DATE NOT NULL,
    `IsActive` TINYINT(1) NOT NULL DEFAULT 1,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
    PRIMARY KEY (`EmployeeId`),
    UNIQUE KEY `UX_Employees_Username` (`Username`),
    KEY `IX_Employees_RoleId` (`RoleId`),
    KEY `IX_Employees_ReportsToEmployeeId` (`ReportsToEmployeeId`),
    CONSTRAINT `FK_Employees_Roles`
        FOREIGN KEY (`RoleId`) REFERENCES `Roles` (`RoleId`),
    CONSTRAINT `FK_Employees_ReportsTo`
        FOREIGN KEY (`ReportsToEmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE `TimeEntries` (
    `TimeEntryId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `ClockInTime` DATETIME(6) NOT NULL,
    `ClockOutTime` DATETIME(6) NULL,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
    PRIMARY KEY (`TimeEntryId`),
    KEY `IX_TimeEntries_EmployeeId` (`EmployeeId`),
    CONSTRAINT `FK_TimeEntries_Employees`
        FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`)
) ENGINE=InnoDB;

CREATE TABLE `LeaveRequests` (
    `LeaveRequestId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `LeaveType` VARCHAR(20) NOT NULL,
    `StartDate` DATE NOT NULL,
    `EndDate` DATE NOT NULL,
    `RequestedHours` DECIMAL(8,2) NOT NULL,
    `ApprovalStatus` VARCHAR(20) NOT NULL DEFAULT 'Pending',
    `Notes` VARCHAR(500) NULL,
    `RequestedAt` DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
    `ApprovedByEmployeeId` INT NULL,
    `ApprovedAt` DATETIME(6) NULL,
    PRIMARY KEY (`LeaveRequestId`),
    KEY `IX_LeaveRequests_EmployeeId` (`EmployeeId`),
    KEY `IX_LeaveRequests_ApprovedByEmployeeId` (`ApprovedByEmployeeId`),
    CONSTRAINT `FK_LeaveRequests_Employees`
        FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `FK_LeaveRequests_Approvers`
        FOREIGN KEY (`ApprovedByEmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `CK_LeaveRequests_Type`
        CHECK (`LeaveType` IN ('Annual', 'Sick', 'Personal')),
    CONSTRAINT `CK_LeaveRequests_Status`
        CHECK (`ApprovalStatus` IN ('Pending', 'Approved', 'Denied', 'Canceled'))
) ENGINE=InnoDB;

CREATE TABLE `LeaveLedger` (
    `LeaveLedgerId` INT NOT NULL AUTO_INCREMENT,
    `EmployeeId` INT NOT NULL,
    `EntryDate` DATE NOT NULL,
    `LeaveType` VARCHAR(20) NOT NULL,
    `Hours` DECIMAL(8,2) NOT NULL,
    `EntryReason` VARCHAR(30) NOT NULL,
    `ReferenceId` INT NULL,
    `Notes` VARCHAR(500) NULL,
    `CreatedAt` DATETIME(6) NOT NULL DEFAULT UTC_TIMESTAMP(6),
    PRIMARY KEY (`LeaveLedgerId`),
    KEY `IX_LeaveLedger_EmployeeId` (`EmployeeId`),
    CONSTRAINT `FK_LeaveLedger_Employees`
        FOREIGN KEY (`EmployeeId`) REFERENCES `Employees` (`EmployeeId`),
    CONSTRAINT `CK_LeaveLedger_Type`
        CHECK (`LeaveType` IN ('Annual', 'Sick', 'Personal')),
    CONSTRAINT `CK_LeaveLedger_Reason`
        CHECK (`EntryReason` IN ('Accrual', 'Usage', 'Adjustment'))
) ENGINE=InnoDB;

DELIMITER $$

CREATE FUNCTION `fn_GetMonthlyAccrualHours`(
    p_HireDate DATE
)
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

DELIMITER $$

CREATE PROCEDURE `usp_CancelLeaveRequest`(
    IN p_LeaveRequestId INT,
    IN p_EmployeeId INT
)
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
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only pending leave requests can be cancelled by the requesting employee.';
    END IF;
END$$

CREATE PROCEDURE `usp_ClockIn`(
    IN p_EmployeeId INT
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM `TimeEntries`
        WHERE `EmployeeId` = p_EmployeeId
          AND `ClockOutTime` IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee is already clocked in.';
    END IF;

    INSERT INTO `TimeEntries` (`EmployeeId`, `ClockInTime`)
    VALUES (p_EmployeeId, UTC_TIMESTAMP(6));
END$$

CREATE PROCEDURE `usp_ClockOut`(
    IN p_EmployeeId INT
)
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
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee is not currently clocked in.';
    END IF;

    UPDATE `TimeEntries`
    SET `ClockOutTime` = UTC_TIMESTAMP(6)
    WHERE `TimeEntryId` = v_TimeEntryId;
END$$

CREATE PROCEDURE `usp_CreateEmployee`(
    IN p_FullName VARCHAR(150),
    IN p_Username VARCHAR(60),
    IN p_RoleName VARCHAR(50),
    IN p_IsHeadStart TINYINT(1),
    IN p_ReportsToEmployeeId INT,
    IN p_HireDate DATE,
    IN p_PasswordSalt VARCHAR(32),
    IN p_PasswordHash VARCHAR(64)
)
BEGIN
    DECLARE v_RoleId INT;
    DECLARE v_ReportsToEmployeeId INT;

    SELECT `RoleId`
    INTO v_RoleId
    FROM `Roles`
    WHERE `RoleName` = p_RoleName
    LIMIT 1;

    IF v_RoleId IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid role name.';
    END IF;

    SET v_ReportsToEmployeeId = p_ReportsToEmployeeId;

    IF p_RoleName = 'Executive Director' THEN
        SET v_ReportsToEmployeeId = NULL;
    END IF;

    INSERT INTO `Employees`
    (
        `FullName`,
        `Username`,
        `IsHeadStart`,
        `ReportsToEmployeeId`,
        `PasswordSalt`,
        `PasswordHash`,
        `MustChangePassword`,
        `RoleId`,
        `HireDate`
    )
    VALUES
    (
        p_FullName,
        p_Username,
        p_IsHeadStart,
        v_ReportsToEmployeeId,
        p_PasswordSalt,
        p_PasswordHash,
        1,
        v_RoleId,
        p_HireDate
    );
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
        CAST(
            CASE
                WHEN `ClockOutTime` IS NULL THEN 0
                ELSE TIMESTAMPDIFF(MINUTE, `ClockInTime`, `ClockOutTime`) / 60.0
            END
            AS DECIMAL(8,2)
        ) AS `WorkedHours`
    FROM `TimeEntries`
    WHERE `EmployeeId` = p_EmployeeId
      AND DATE(`ClockInTime`) BETWEEN p_PeriodStartDate AND v_PeriodEndDate
    ORDER BY `ClockInTime`;
END$$

CREATE PROCEDURE `usp_PostMonthlyLeaveAccruals`(
    IN p_AccrualDate DATE
)
BEGIN
    DECLARE v_EffectiveDate DATE;

    SET v_EffectiveDate = IFNULL(p_AccrualDate, LAST_DAY(CURDATE()));

    INSERT INTO `LeaveLedger`
    (
        `EmployeeId`,
        `EntryDate`,
        `LeaveType`,
        `Hours`,
        `EntryReason`,
        `Notes`
    )
    SELECT
        E.`EmployeeId`,
        v_EffectiveDate,
        LT.`LeaveType`,
        `fn_GetMonthlyAccrualHours`(E.`HireDate`),
        'Accrual',
        CONCAT('Monthly accrual for ', YEAR(v_EffectiveDate), '-', LPAD(MONTH(v_EffectiveDate), 2, '0'))
    FROM `Employees` E
    JOIN (
        SELECT 'Sick' AS `LeaveType`
        UNION ALL
        SELECT 'Annual'
        UNION ALL
        SELECT 'Personal'
    ) LT
      ON (
          (LT.`LeaveType` = 'Sick')
          OR (LT.`LeaveType` = 'Annual' AND E.`IsHeadStart` = 0)
          OR (LT.`LeaveType` = 'Personal' AND E.`IsHeadStart` = 1)
      )
    WHERE E.`IsActive` = 1
      AND NOT EXISTS
      (
          SELECT 1
          FROM `LeaveLedger` L
          WHERE L.`EmployeeId` = E.`EmployeeId`
            AND L.`LeaveType` = LT.`LeaveType`
            AND L.`EntryReason` = 'Accrual'
            AND YEAR(L.`EntryDate`) = YEAR(v_EffectiveDate)
            AND MONTH(L.`EntryDate`) = MONTH(v_EffectiveDate)
      );
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

    SELECT
        `EmployeeId`,
        `LeaveType`,
        `RequestedHours`
    INTO
        v_EmployeeId,
        v_LeaveType,
        v_RequestedHours
    FROM `LeaveRequests`
    WHERE `LeaveRequestId` = p_LeaveRequestId
      AND `ApprovalStatus` = 'Pending'
    LIMIT 1;

    IF v_EmployeeId IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Leave request was not found or is already processed.';
    END IF;

    IF p_ApprovalStatus = 'Approved' THEN
        SELECT
            CASE
                WHEN v_LeaveType = 'Annual' THEN `AnnualLeaveHours`
                WHEN v_LeaveType = 'Personal' THEN `PersonalLeaveHours`
                ELSE `SickLeaveHours`
            END
        INTO v_CurrentBalance
        FROM `vw_EmployeeLeaveBalances`
        WHERE `EmployeeId` = v_EmployeeId;

        IF IFNULL(v_CurrentBalance, 0) < v_RequestedHours THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Insufficient leave balance.';
        END IF;

        INSERT INTO `LeaveLedger`
        (
            `EmployeeId`,
            `EntryDate`,
            `LeaveType`,
            `Hours`,
            `EntryReason`,
            `ReferenceId`,
            `Notes`
        )
        VALUES
        (
            v_EmployeeId,
            CURRENT_DATE(),
            v_LeaveType,
            v_RequestedHours * -1,
            'Usage',
            p_LeaveRequestId,
            'Approved leave request'
        );
    END IF;

    UPDATE `LeaveRequests`
    SET `ApprovalStatus` = p_ApprovalStatus,
        `ApprovedByEmployeeId` = p_ApprovedByEmployeeId,
        `ApprovedAt` = UTC_TIMESTAMP(6)
    WHERE `LeaveRequestId` = p_LeaveRequestId;
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
    DECLARE v_IsHeadStart TINYINT(1);

    SELECT `IsHeadStart`
    INTO v_IsHeadStart
    FROM `Employees`
    WHERE `EmployeeId` = p_EmployeeId
    LIMIT 1;

    IF p_EndDate < p_StartDate THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'End date cannot be earlier than start date.';
    END IF;

    IF v_IsHeadStart = 1 AND p_LeaveType = 'Annual' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Head Start employees accrue Personal leave instead of Annual leave.';
    END IF;

    IF IFNULL(v_IsHeadStart, 0) = 0 AND p_LeaveType = 'Personal' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only Head Start employees can request Personal leave.';
    END IF;

    INSERT INTO `LeaveRequests`
    (
        `EmployeeId`,
        `LeaveType`,
        `StartDate`,
        `EndDate`,
        `RequestedHours`,
        `Notes`
    )
    VALUES
    (
        p_EmployeeId,
        p_LeaveType,
        p_StartDate,
        p_EndDate,
        p_RequestedHours,
        p_Notes
    );
END$$

CREATE PROCEDURE `usp_UpdateEmployee`(
    IN p_EmployeeId INT,
    IN p_FullName VARCHAR(150),
    IN p_Username VARCHAR(60),
    IN p_RoleName VARCHAR(50),
    IN p_IsHeadStart TINYINT(1),
    IN p_ReportsToEmployeeId INT,
    IN p_HireDate DATE,
    IN p_IsActive TINYINT(1)
)
BEGIN
    DECLARE v_RoleId INT;
    DECLARE v_ReportsToEmployeeId INT;

    SELECT `RoleId`
    INTO v_RoleId
    FROM `Roles`
    WHERE `RoleName` = p_RoleName
    LIMIT 1;

    IF v_RoleId IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid role name.';
    END IF;

    SET v_ReportsToEmployeeId = p_ReportsToEmployeeId;

    IF p_RoleName = 'Executive Director' THEN
        SET v_ReportsToEmployeeId = NULL;
    END IF;

    UPDATE `Employees`
    SET `FullName` = p_FullName,
        `Username` = p_Username,
        `IsHeadStart` = p_IsHeadStart,
        `ReportsToEmployeeId` = v_ReportsToEmployeeId,
        `RoleId` = v_RoleId,
        `HireDate` = p_HireDate,
        `IsActive` = p_IsActive
    WHERE `EmployeeId` = p_EmployeeId;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee not found.';
    END IF;
END$$

DELIMITER ;
