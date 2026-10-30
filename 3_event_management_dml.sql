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
