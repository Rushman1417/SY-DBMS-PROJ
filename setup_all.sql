-- =====================================================
-- Event Management System — Database Schema (DDL)
-- Works on MySQL 8.0+ and MariaDB 10.4+ (XAMPP)
-- 7 tables + 1 view, PK/FK constraints, cascaded delete/update
--
-- RUN ORDER: 1_ddl -> 2_triggers_procedures -> 3_dml -> 4_dcl
-- (or just run setup_all.sql, which is all four in order)
-- =====================================================

-- Start clean so the whole setup can be re-run any number of times
DROP DATABASE IF EXISTS event_management_system;
CREATE DATABASE event_management_system;
USE event_management_system;

-- ---------------------------------------------------
-- 1. CLUBS — organizations that host events
-- ---------------------------------------------------
CREATE TABLE Clubs (
    club_id      INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    description  VARCHAR(255),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------
-- 2. VENUES — physical locations events are held at
-- ---------------------------------------------------
CREATE TABLE Venues (
    venue_id   INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    location   VARCHAR(150) NOT NULL,
    capacity   INT NOT NULL CHECK (capacity > 0)
);

-- ---------------------------------------------------
-- 3. USERS — both admins and normal (student) users
-- ---------------------------------------------------
CREATE TABLE Users (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    name           VARCHAR(100) NOT NULL,
    email          VARCHAR(100) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    role           ENUM('admin', 'normal') NOT NULL DEFAULT 'normal',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------
-- 4. EVENTS — one club hosts, one venue holds
-- ---------------------------------------------------
CREATE TABLE Events (
    event_id     INT AUTO_INCREMENT PRIMARY KEY,
    club_id      INT NOT NULL,
    venue_id     INT NOT NULL,
    name         VARCHAR(150) NOT NULL,
    event_date   DATE NOT NULL,
    start_time   TIME,
    capacity     INT NOT NULL CHECK (capacity > 0),
    status       ENUM('Open', 'Full', 'Cancelled', 'Completed') NOT NULL DEFAULT 'Open',
    FOREIGN KEY (club_id)  REFERENCES Clubs(club_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (venue_id) REFERENCES Venues(venue_id)
        ON DELETE RESTRICT ON UPDATE CASCADE   -- don't silently delete events if a venue record is removed
);

-- ---------------------------------------------------
-- 5. REGISTRATIONS — many-to-many: Users <-> Events
-- ---------------------------------------------------
CREATE TABLE Registrations (
    registration_id  INT AUTO_INCREMENT PRIMARY KEY,
    event_id         INT NOT NULL,
    user_id          INT NOT NULL,
    reg_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           ENUM('Confirmed', 'Cancelled', 'Waitlisted') NOT NULL DEFAULT 'Confirmed',
    FOREIGN KEY (event_id) REFERENCES Events(event_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (user_id)  REFERENCES Users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    UNIQUE (event_id, user_id)   -- one row per user per event; re-registering after
                                 -- a cancellation re-activates that same row
);

-- ---------------------------------------------------
-- 6. VOLUNTEERS — many-to-many: Users <-> Events
-- ---------------------------------------------------
CREATE TABLE Volunteers (
    volunteer_id   INT AUTO_INCREMENT PRIMARY KEY,
    event_id       INT NOT NULL,
    user_id        INT NOT NULL,
    role_assigned  VARCHAR(100),
    FOREIGN KEY (event_id) REFERENCES Events(event_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (user_id)  REFERENCES Users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    UNIQUE (event_id, user_id)   -- a user can only hold one volunteer slot per event
);

-- ---------------------------------------------------
-- 7. PAYMENTS — one-to-one/optional per registration
-- ---------------------------------------------------
CREATE TABLE Payments (
    payment_id       INT AUTO_INCREMENT PRIMARY KEY,
    registration_id  INT NOT NULL,
    amount           DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    payment_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           ENUM('Pending', 'Paid', 'Refunded') NOT NULL DEFAULT 'Pending',
    FOREIGN KEY (registration_id) REFERENCES Registrations(registration_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- ---------------------------------------------------
-- VIEW: UserDirectory — Users WITHOUT password_hash
-- The public app needs to look students up by email, but
-- must never be able to read password hashes. normal_user
-- gets SELECT on this view only, never on the Users table.
-- ---------------------------------------------------
CREATE VIEW UserDirectory AS
SELECT user_id, name, email, role
FROM Users;
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
-- =====================================================
-- Event Management System — DML
-- Sample data (real MIT-WPU clubs) + Insert / Update /
-- Delete / Search queries
--
-- Event dates are relative to CURDATE(), so the events are
-- always "upcoming" no matter which day you run this.
-- =====================================================

USE event_management_system;

-- =====================================================
-- SAMPLE DATA (INSERT)
-- =====================================================

INSERT INTO Clubs (name, description) VALUES
('Synapse Club', 'AI and machine learning club at MIT-WPU'),
('Innovation Wing', 'Hackathon and project-focused club wing at MIT-WPU'),
('INIT-Cloud Club', 'Cloud computing and coding community at MIT-WPU'),
('Nummerates', 'Academic excellence and technical interview prep club'),
('Dadasaheb Phalke Film School', 'Organizers of the Student Film Festival of India (STUFFI)');

INSERT INTO Venues (name, location, capacity) VALUES
('Seminar Hall 2', 'Block C, 2nd Floor, MIT-WPU Kothrud Campus', 120),
('Main Auditorium', 'Block A, Ground Floor, MIT-WPU Kothrud Campus', 500),
('Film School Screening Room', 'Dadasaheb Phalke Film School Building, MIT-WPU', 80);

-- The admin's password_hash is a real bcrypt hash of 'admin123'
-- (generated with PHP's password_hash) so the admin page login works.
-- Students don't log in in this project, so theirs are placeholders.
INSERT INTO Users (name, email, password_hash, role) VALUES
('Admin User',   'admin@mitwpu.edu.in',  '$2y$10$EXRuXK1hArXn6EXNzg1xAui.T.Un1PTyB2LbYB8ehh1ZOVxgVUxfC', 'admin'),
('Labdhi Shah',  'labdhi@mitwpu.edu.in', 'hashed_pw_2', 'normal'),
('Rohan Mehta',  'rohan@mitwpu.edu.in',  'hashed_pw_3', 'normal'),
('Ayesha Khan',  'ayesha@mitwpu.edu.in', 'hashed_pw_4', 'normal'),
('Priya Nair',   'priya@mitwpu.edu.in',  'hashed_pw_5', 'normal'),
('Karan Joshi',  'karan@mitwpu.edu.in',  'hashed_pw_6', 'normal');

-- Event 1 is deliberately seeded near its capacity (3, with 2 confirmed
-- registrations already) so registering just ONE more person through the
-- frontend is enough to trigger trg_update_event_status, and a second
-- attempt after that demonstrates trg_prevent_overbooking rejecting it.
INSERT INTO Events (club_id, venue_id, name, event_date, start_time, capacity, status) VALUES
(1, 1, 'AI Hackathon 2026',                CURDATE() + INTERVAL 12 DAY, '09:00:00', 3,   'Open'),
(3, 1, 'Cloud Computing Meetup',           CURDATE() + INTERVAL 19 DAY, '15:00:00', 60,  'Open'),
(4, 2, 'Technical Interview Prep Session', CURDATE() + INTERVAL 16 DAY, '17:00:00', 200, 'Open'),
(5, 3, 'STUFFI Submission Info Session',   CURDATE() + INTERVAL 23 DAY, '11:00:00', 80,  'Open');

INSERT INTO Registrations (event_id, user_id, status) VALUES
(1, 2, 'Confirmed'),   -- Labdhi -> AI Hackathon
(1, 3, 'Confirmed'),   -- Rohan  -> AI Hackathon (2/3 filled — 1 seat left)
(2, 2, 'Confirmed'),   -- Labdhi -> Cloud Computing Meetup
(3, 4, 'Confirmed'),   -- Ayesha -> Technical Interview Prep Session
(4, 4, 'Confirmed');   -- Ayesha -> STUFFI Info Session

INSERT INTO Volunteers (event_id, user_id, role_assigned) VALUES
(1, 4, 'Registration Desk'),   -- Ayesha volunteers at AI Hackathon
(2, 3, 'Logistics');           -- Rohan volunteers at Cloud Computing Meetup

INSERT INTO Payments (registration_id, amount, status) VALUES
(1, 100.00, 'Paid'),      -- Labdhi's AI Hackathon ticket
(2, 100.00, 'Pending'),   -- Rohan's AI Hackathon ticket
(3, 50.00, 'Paid');       -- Labdhi's Cloud Computing Meetup ticket


-- =====================================================
-- INSERTION — adding a new registration
-- =====================================================
INSERT INTO Registrations (event_id, user_id, status)
VALUES (2, 4, 'Confirmed');   -- Ayesha also joins the Cloud Computing Meetup


-- =====================================================
-- UPDATION — mark a pending payment as paid
-- =====================================================
UPDATE Payments
SET status = 'Paid', payment_date = CURRENT_TIMESTAMP
WHERE registration_id = 2;

-- Updation — reschedule an event's date (pushed back two days)
UPDATE Events
SET event_date = event_date + INTERVAL 2 DAY
WHERE event_id = 1;


-- =====================================================
-- DELETION — cancel a registration
-- (cascades automatically to its Payment row, since
--  Payments.registration_id -> Registrations ON DELETE CASCADE)
-- =====================================================
DELETE FROM Registrations
WHERE registration_id = 3;   -- Labdhi's Cloud Meetup registration + its Payment both disappear

-- Deletion — remove an entire event
-- (cascades to any Registrations, Volunteers, and Payments tied to it —
--  here it removes Ayesha's Technical Interview Prep Session registration)
DELETE FROM Events
WHERE event_id = 3;


-- =====================================================
-- SEARCHING — everyday query patterns
-- =====================================================

-- 1. All upcoming events with their venue and hosting club
SELECT e.name AS event_name, e.event_date, v.name AS venue, c.name AS club
FROM Events e
JOIN Venues v ON e.venue_id = v.venue_id
JOIN Clubs c ON e.club_id = c.club_id
WHERE e.event_date >= CURDATE()
ORDER BY e.event_date;

-- 2. All students registered for a specific event
SELECT u.name, u.email, r.status, r.reg_date
FROM Registrations r
JOIN Users u ON r.user_id = u.user_id
WHERE r.event_id = 1;

-- 3. Search events by partial name match
SELECT event_id, name, event_date, status
FROM Events
WHERE name LIKE '%Hackathon%';

-- 4. Count of confirmed registrations per event (seats filled)
SELECT e.name, COUNT(r.registration_id) AS seats_filled, e.capacity
FROM Events e
LEFT JOIN Registrations r
       ON e.event_id = r.event_id AND r.status = 'Confirmed'
GROUP BY e.event_id, e.name, e.capacity;

-- 5. All events a specific user has volunteered for
SELECT e.name, vol.role_assigned
FROM Volunteers vol
JOIN Events e ON vol.event_id = e.event_id
WHERE vol.user_id = 3;

-- 6. Total revenue collected per event
SELECT e.name, SUM(p.amount) AS total_revenue
FROM Events e
JOIN Registrations r ON e.event_id = r.event_id
JOIN Payments p ON r.registration_id = p.registration_id
WHERE p.status = 'Paid'
GROUP BY e.event_id, e.name;
-- =====================================================
-- Event Management System — DCL
-- Two user types: admin (full control) and normal
-- (students who browse events, register and cancel)
--
-- Principle: least privilege. normal_user gets exactly
-- what the public pages use, and nothing more.
-- =====================================================

USE event_management_system;

-- =====================================================
-- CREATE MYSQL USERS (dropped first so re-running this
-- script never leaves stale privileges behind)
-- =====================================================
DROP USER IF EXISTS 'admin_user'@'localhost';
DROP USER IF EXISTS 'normal_user'@'localhost';

CREATE USER 'admin_user'@'localhost'  IDENTIFIED BY 'AdminPass@123';
CREATE USER 'normal_user'@'localhost' IDENTIFIED BY 'NormalPass@123';


-- =====================================================
-- ADMIN — full control over every table, procedure and
-- function in this database (ALL PRIVILEGES includes EXECUTE)
-- =====================================================
GRANT ALL PRIVILEGES ON event_management_system.* TO 'admin_user'@'localhost';

-- The admin page also shows SHOW GRANTS for both roles.
-- Reading ANOTHER account's grants requires SELECT on the
-- mysql system database. This is read-only, and it's the
-- only thing admin_user has outside this project's database.
GRANT SELECT ON mysql.* TO 'admin_user'@'localhost';


-- =====================================================
-- NORMAL USER — a student
-- =====================================================

-- Read-only access to what the events page displays
GRANT SELECT ON event_management_system.Clubs  TO 'normal_user'@'localhost';
GRANT SELECT ON event_management_system.Venues TO 'normal_user'@'localhost';
GRANT SELECT ON event_management_system.Events TO 'normal_user'@'localhost';

-- Look students up by email through the view, which has no
-- password_hash column. No privilege at all on Users itself.
GRANT SELECT ON event_management_system.UserDirectory TO 'normal_user'@'localhost';

-- Payments and Volunteers: deliberately NOT granted.
-- Students have no page that needs them, and payments are
-- other people's financial records.

-- Registrations: grant broad first...
GRANT SELECT, INSERT, DELETE ON event_management_system.Registrations
    TO 'normal_user'@'localhost';

-- ...UPDATE only on the status column (column-level privilege).
-- A student can cancel or re-confirm a registration, but can't
-- move it to another event or reassign it to another user_id.
GRANT UPDATE (status) ON event_management_system.Registrations
    TO 'normal_user'@'localhost';

-- ...then revoke the one privilege that shouldn't be there.
-- Hard-deleting a registration is an admin-only action; students
-- cancel by setting status = 'Cancelled', which keeps the record.
REVOKE DELETE ON event_management_system.Registrations
    FROM 'normal_user'@'localhost';

-- (No FLUSH PRIVILEGES needed: GRANT/REVOKE take effect
--  immediately. FLUSH is only for direct edits to mysql.* tables.)


-- =====================================================
-- VERIFY — check what each role actually ended up with
-- =====================================================
SHOW GRANTS FOR 'admin_user'@'localhost';
SHOW GRANTS FOR 'normal_user'@'localhost';
