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
