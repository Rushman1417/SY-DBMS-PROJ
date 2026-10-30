# MIT-WPU Campus Events — DBMS Mini Project

Event management system in PHP + MySQL/MariaDB, demonstrating DDL, DML,
DCL, triggers, stored procedures and a stored function.

Tested end to end on MariaDB 10.11 and PHP 8.3. Works with XAMPP and
with MySQL 8.0+.

## Running it (XAMPP on Windows/Mac)

1. Copy this whole `event_management` folder into `C:\xampp\htdocs\`
   (Mac: `/Applications/XAMPP/htdocs/`).
2. Start **Apache** and **MySQL** from the XAMPP Control Panel.
3. Open http://localhost/phpmyadmin, click the **Import** tab, choose
   `sql/setup_all.sql` and click **Import**.
   (Or from a terminal: `mysql -u root -p < sql/setup_all.sql`)
4. Open http://localhost/event_management/

`setup_all.sql` is the four SQL files joined in the right order. It drops
and recreates everything, so you can re-run it any time to reset the demo.
If you'd rather run the files one by one, the order is:

1. `1_event_management_ddl.sql`
2. `2_event_management_triggers_procedures.sql`
3. `3_event_management_dml.sql`
4. `4_event_management_dcl.sql`

No passwords need editing. The app connects as `normal_user` and
`admin_user` (created by the DCL script), never as root.

## Demo accounts

| Who | Email | Notes |
|---|---|---|
| Admin | admin@mitwpu.edu.in | password `admin123` (admin page only) |
| Labdhi | labdhi@mitwpu.edu.in | already registered for AI Hackathon |
| Rohan | rohan@mitwpu.edu.in | already registered for AI Hackathon |
| Ayesha | ayesha@mitwpu.edu.in | not yet in AI Hackathon |
| Priya | priya@mitwpu.edu.in | free |
| Karan | karan@mitwpu.edu.in | free |

Students register and cancel with just their email.

## Demo script for the viva (about 3 minutes)

1. **Home page.** AI Hackathon shows "1 seat left" (capacity 3, 2 booked).
2. **Fill the last seat.** Register for AI Hackathon as
   `ayesha@mitwpu.edu.in`. Go back: it now says **Full**.
   *trg_update_event_status* flipped `Events.status` automatically.
3. **Overbooking blocked.** Open
   `localhost/event_management/register.php?event_id=1` directly and try
   `priya@mitwpu.edu.in`. The error comes from *trg_prevent_overbooking*
   via `SIGNAL SQLSTATE '45000'`, not from PHP.
4. **Cancellation reopens it.** Click "Cancel my registration" on AI
   Hackathon and enter `rohan@mitwpu.edu.in`. The event goes back to
   "1 seat left" (*trg_sync_status_on_update*).
5. **Admin page.** Log in as admin. Show revenue from the
   *GetEventRevenue* procedure, seats from the *GetAvailableSeats*
   function, the registrations table, and the live `SHOW GRANTS` output.
6. **Cancelled event.** Click "Cancel event" on Cloud Computing Meetup.
   The home page shows it greyed out with no Register button, and the
   trigger rejects registrations even via the direct URL.
7. **DCL proof** (optional, in a MySQL terminal):
   ```
   mysql -u normal_user -pNormalPass@123 event_management_system
   SELECT * FROM Users;                          -- denied (password hashes)
   SELECT * FROM Payments;                       -- denied
   DELETE FROM Registrations WHERE registration_id = 1;  -- denied (revoked)
   UPDATE Registrations SET user_id = 6 WHERE registration_id = 1;  -- denied (column-level)
   SELECT * FROM UserDirectory;                  -- allowed (view, no hashes)
   ```

## What each database object does

**Triggers** (all on `Registrations`)

| Trigger | When | Does |
|---|---|---|
| `trg_prevent_overbooking` | BEFORE INSERT | Rejects if event is full, cancelled or completed |
| `trg_prevent_overbooking_on_update` | BEFORE UPDATE | Same check when a cancelled registration is re-confirmed |
| `trg_update_event_status` | AFTER INSERT | Flips event to Full when the last seat goes |
| `trg_sync_status_on_update` | AFTER UPDATE | Flips Full back to Open after a cancellation |
| `trg_sync_status_on_delete` | AFTER DELETE | Same, when an admin hard-deletes a registration |

**Procedures and function**

- `GetEventRevenue(event_id, OUT total)`: required procedure, sum of paid payments.
- `GetAvailableSeats(event_id)`: function, seats remaining.
- `CheckSeatAvailable(event_id)`: helper called by both "prevent" triggers,
  so the capacity rule lives in one place. Locks the event row with
  `SELECT ... FOR UPDATE`, so two students grabbing the last seat at the same
  instant can't both get it. (Tested: 3 simultaneous requests for 1 seat
  gave exactly 1 success.)
- `SyncEventStatus(event_id)`: helper called by the AFTER triggers,
  recalculates Open/Full.

**DCL**

- `admin_user`: `ALL PRIVILEGES` on the project database, plus read-only
  `SELECT` on the `mysql` schema, which MySQL requires to run `SHOW GRANTS`
  for another account.
- `normal_user`: `SELECT` on Clubs, Venues, Events and the `UserDirectory`
  view; `SELECT, INSERT` on Registrations; `UPDATE` on the `status` column
  only. `DELETE` is granted and then `REVOKE`d to demonstrate REVOKE.
  No access to Users, Payments or Volunteers.

Triggers and procedures run with their creator's (root's) privileges. That's
why `normal_user`, which has no UPDATE on Events, can still cause
`Events.status` to change.

## Known limitations (good to state honestly if asked)

- Students are identified by email only, with no password. Anyone who knows
  a student's email could register or cancel on their behalf. A real system
  would add student login using `password_hash` / `password_verify`, the
  same way the admin page already works.
- Cancelling a registration doesn't refund its payment (students have no
  access to Payments by design; refunds would be an admin action).
- Database passwords are in `config.php` in plain text, which is fine for
  a local project. In production they'd come from environment variables.
