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
