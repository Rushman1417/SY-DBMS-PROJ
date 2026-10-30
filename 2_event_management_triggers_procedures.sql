-- =====================================================
-- Event Management System — Triggers + Procedures/Function
-- Run AFTER the DDL and BEFORE the DML, so the sample
-- data is inserted with the triggers already active.
-- =====================================================

USE event_management_system;

DROP TRIGGER   IF EXISTS trg_prevent_overbooking;
DROP TRIGGER   IF EXISTS trg_prevent_overbooking_on_update;
DROP TRIGGER   IF EXISTS trg_update_event_status;
DROP TRIGGER   IF EXISTS trg_sync_status_on_update;
DROP TRIGGER   IF EXISTS trg_sync_status_on_delete;
DROP PROCEDURE IF EXISTS CheckSeatAvailable;
DROP PROCEDURE IF EXISTS SyncEventStatus;
DROP PROCEDURE IF EXISTS GetEventRevenue;
DROP FUNCTION  IF EXISTS GetAvailableSeats;


-- =====================================================
-- HELPER PROCEDURE: CheckSeatAvailable
-- Shared by both "prevent overbooking" triggers (insert
-- and update), so the rule lives in exactly one place.
--
-- 1. Locks the event's row (SELECT ... FOR UPDATE). If two
--    students try to take the last seat at the same moment,
--    the second one waits here until the first commits, then
--    counts again and is correctly rejected. Without the lock,
--    both could read "1 seat left" and both get in.
-- 2. Rejects registrations for Cancelled / Completed events.
-- 3. Rejects once confirmed registrations reach capacity.
-- =====================================================
DELIMITER $$

CREATE PROCEDURE CheckSeatAvailable(IN p_event_id INT)
BEGIN
    DECLARE v_capacity INT DEFAULT NULL;
    DECLARE v_status   VARCHAR(20) DEFAULT NULL;
    DECLARE v_count    INT DEFAULT 0;

    SELECT capacity, status INTO v_capacity, v_status
    FROM Events
    WHERE event_id = p_event_id
    FOR UPDATE;

    -- Event doesn't exist: do nothing here and let the
    -- foreign key reject the row with its own error (1452).
    IF v_capacity IS NOT NULL THEN
        IF v_status IN ('Cancelled', 'Completed') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Registration failed: this event is no longer accepting registrations';
        END IF;

        SELECT COUNT(*) INTO v_count
        FROM Registrations
        WHERE event_id = p_event_id AND status = 'Confirmed';

        IF v_count >= v_capacity THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Registration failed: this event has reached full capacity';
        END IF;
    END IF;
END$$

DELIMITER ;


-- =====================================================
-- HELPER PROCEDURE: SyncEventStatus
-- Recounts confirmed registrations and flips the event
-- between 'Open' and 'Full' in BOTH directions. Events an
-- admin has marked Cancelled/Completed are left alone.
-- =====================================================
DELIMITER $$

CREATE PROCEDURE SyncEventStatus(IN p_event_id INT)
BEGIN
    UPDATE Events e
    SET e.status = CASE
            WHEN (SELECT COUNT(*) FROM Registrations r
                  WHERE r.event_id = e.event_id AND r.status = 'Confirmed') >= e.capacity
            THEN 'Full'
            ELSE 'Open'
        END
    WHERE e.event_id = p_event_id
      AND e.status IN ('Open', 'Full');
END$$

DELIMITER ;


-- =====================================================
-- TRIGGER 1 (required): prevent overbooking on INSERT
-- =====================================================
DELIMITER $$

CREATE TRIGGER trg_prevent_overbooking
BEFORE INSERT ON Registrations
FOR EACH ROW
BEGIN
    IF NEW.status = 'Confirmed' THEN
        CALL CheckSeatAvailable(NEW.event_id);
    END IF;
END$$

DELIMITER ;


-- =====================================================
-- TRIGGER 1b: prevent overbooking on UPDATE
-- Closes the loophole where a Cancelled registration is
-- switched back to 'Confirmed' (re-registering) on a full
-- event — that's an UPDATE, so the INSERT trigger never fires.
-- =====================================================
DELIMITER $$

CREATE TRIGGER trg_prevent_overbooking_on_update
BEFORE UPDATE ON Registrations
FOR EACH ROW
BEGIN
    IF NEW.status = 'Confirmed'
       AND (OLD.status <> 'Confirmed' OR OLD.event_id <> NEW.event_id) THEN
        CALL CheckSeatAvailable(NEW.event_id);
    END IF;
END$$

DELIMITER ;


-- =====================================================
-- TRIGGER 2 (bonus): flip event to 'Full' after the
-- registration that takes the last seat
-- =====================================================
DELIMITER $$

CREATE TRIGGER trg_update_event_status
AFTER INSERT ON Registrations
FOR EACH ROW
BEGIN
    CALL SyncEventStatus(NEW.event_id);
END$$

DELIMITER ;


-- =====================================================
-- TRIGGER 3: re-sync status after a registration changes
-- A cancellation frees a seat, so a 'Full' event goes back
-- to 'Open'. A re-confirmation can make it 'Full' again.
-- =====================================================
DELIMITER $$

CREATE TRIGGER trg_sync_status_on_update
AFTER UPDATE ON Registrations
FOR EACH ROW
BEGIN
    CALL SyncEventStatus(NEW.event_id);
    IF OLD.event_id <> NEW.event_id THEN
        CALL SyncEventStatus(OLD.event_id);
    END IF;
END$$

DELIMITER ;


-- =====================================================
-- TRIGGER 4: re-sync status after an admin hard-deletes
-- a registration
-- =====================================================
DELIMITER $$

CREATE TRIGGER trg_sync_status_on_delete
AFTER DELETE ON Registrations
FOR EACH ROW
BEGIN
    CALL SyncEventStatus(OLD.event_id);
END$$

DELIMITER ;


-- =====================================================
-- PROCEDURE (required): total revenue collected for an event
-- =====================================================
DELIMITER $$

CREATE PROCEDURE GetEventRevenue(IN p_event_id INT, OUT p_total DECIMAL(10,2))
BEGIN
    SELECT COALESCE(SUM(p.amount), 0) INTO p_total
    FROM Payments p
    JOIN Registrations r ON p.registration_id = r.registration_id
    WHERE r.event_id = p_event_id AND p.status = 'Paid';
END$$

DELIMITER ;

-- Usage:
-- CALL GetEventRevenue(1, @total);
-- SELECT @total AS total_revenue;


-- =====================================================
-- FUNCTION (bonus): available seats remaining for an event
-- NOT DETERMINISTIC: the same event_id gives a different
-- answer as registrations change, so declaring it
-- DETERMINISTIC would be incorrect.
-- =====================================================
DELIMITER $$

CREATE FUNCTION GetAvailableSeats(p_event_id INT) RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE seats_left INT DEFAULT NULL;

    SELECT GREATEST(e.capacity - COUNT(r.registration_id), 0) INTO seats_left
    FROM Events e
    LEFT JOIN Registrations r
           ON e.event_id = r.event_id AND r.status = 'Confirmed'
    WHERE e.event_id = p_event_id
    GROUP BY e.capacity;

    RETURN seats_left;   -- NULL if the event doesn't exist
END$$

DELIMITER ;

-- Usage:
-- SELECT GetAvailableSeats(1);
