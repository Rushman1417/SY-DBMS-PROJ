<?php
// Admin demo page.
// Connects as admin_user (from the DCL script), not root, and is protected
// by a login checked against the Users table (role = 'admin'), using
// PHP's password_verify() on the stored bcrypt hash.

session_start();
require 'db_admin_connect.php';

$loginError = '';
$flash = '';

// ---- Logout ----
if (isset($_GET['logout'])) {
    $_SESSION = [];
    session_destroy();
    header("Location: admin.php");
    exit;
}

// ---- Login ----
if (!isset($_SESSION['admin_id']) && ($_POST['action'] ?? '') === 'login') {
    $email    = strtolower(trim($_POST['email'] ?? ''));
    $password = $_POST['password'] ?? '';

    $stmt = $conn->prepare(
        "SELECT user_id, name, password_hash FROM Users WHERE email = ? AND role = 'admin'"
    );
    $stmt->bind_param("s", $email);
    $stmt->execute();
    $admin = $stmt->get_result()->fetch_assoc();

    if ($admin && password_verify($password, $admin['password_hash'])) {
        session_regenerate_id(true);
        $_SESSION['admin_id']   = (int)$admin['user_id'];
        $_SESSION['admin_name'] = $admin['name'];
        header("Location: admin.php");
        exit;
    }
    $loginError = "Email or password is incorrect.";
}

$loggedIn = isset($_SESSION['admin_id']);

// ---- Admin actions: cancel / reopen an event ----
if ($loggedIn && in_array($_POST['action'] ?? '', ['cancel_event', 'reopen_event'], true)) {
    $eventId = (int)($_POST['event_id'] ?? 0);

    if ($_POST['action'] === 'cancel_event') {
        $stmt = $conn->prepare("UPDATE Events SET status = 'Cancelled' WHERE event_id = ?");
        $stmt->bind_param("i", $eventId);
        $stmt->execute();
        $flash = "Event cancelled. It now shows as Cancelled and the trigger rejects new registrations.";
    } else {
        // Set back to Open, then let SyncEventStatus decide Open vs Full
        $stmt = $conn->prepare("UPDATE Events SET status = 'Open' WHERE event_id = ?");
        $stmt->bind_param("i", $eventId);
        $stmt->execute();
        $stmt = $conn->prepare("CALL SyncEventStatus(?)");
        $stmt->bind_param("i", $eventId);
        $stmt->execute();
        $flash = "Event reopened. Its status was recalculated from confirmed registrations.";
    }
}

if ($loggedIn) {
    // ---- Call the stored procedure + function for every event ----
    $events = $conn->query("SELECT event_id, name, event_date, status, capacity FROM Events ORDER BY event_date");
    $eventStats = [];
    $revStmt = $conn->prepare("CALL GetEventRevenue(?, @total)");
    while ($ev = $events->fetch_assoc()) {
        $eventId = (int)$ev['event_id'];

        $revStmt->bind_param("i", $eventId);
        $revStmt->execute();
        $revenue = $conn->query("SELECT @total AS total")->fetch_assoc()['total'];

        $seats = $conn->query("SELECT GetAvailableSeats($eventId) AS seats")->fetch_assoc()['seats'];

        $eventStats[] = $ev + ['revenue' => $revenue, 'seats' => $seats];
    }

    // ---- All registrations, to watch the triggers work ----
    $registrations = $conn->query(
        "SELECT r.registration_id, e.name AS event_name, u.name AS student, u.email, r.status, r.reg_date
         FROM Registrations r
         JOIN Events e ON r.event_id = e.event_id
         JOIN Users u  ON r.user_id  = u.user_id
         ORDER BY e.event_date, r.reg_date"
    )->fetch_all(MYSQLI_ASSOC);

    // ---- Read the actual DCL privilege grants in effect ----
    $grants = [];
    foreach (['admin_user', 'normal_user'] as $role) {
        $grants[$role] = [];
        $res = $conn->query("SHOW GRANTS FOR '$role'@'localhost'");
        while ($row = $res->fetch_row()) {
            // Hide the password hash MariaDB includes in the USAGE line
            $grants[$role][] = preg_replace("/ IDENTIFIED BY PASSWORD '[^']*'/", "", $row[0]);
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Admin — Procedure, Function &amp; DCL</title>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:wght@500;600&family=IBM+Plex+Sans:wght@400;500&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="style.css">
</head>
<body>

<header class="site-header">
  <div class="crest-row">
    <h1>Admin Demo</h1>
    <span class="tagline">
      <a href="index.php">&larr; back to events</a>
      <?php if ($loggedIn): ?>
        &nbsp;|&nbsp; <?= htmlspecialchars($_SESSION['admin_name']) ?> &middot; <a href="admin.php?logout=1">Log out</a>
      <?php endif; ?>
    </span>
  </div>
</header>

<?php if (!$loggedIn): ?>

<div class="form-card">
  <?php if ($loginError): ?>
    <div class="error-banner"><?= htmlspecialchars($loginError) ?></div>
  <?php endif; ?>
  <h3>Admin login</h3>
  <form method="POST">
    <input type="hidden" name="action" value="login">
    <label for="email">Email</label>
    <input type="email" id="email" name="email" required placeholder="admin@mitwpu.edu.in"
           value="<?= htmlspecialchars($_POST['email'] ?? '') ?>">
    <label for="password">Password</label>
    <input type="password" id="password" name="password" required>
    <button type="submit" class="btn">Log in</button>
  </form>
</div>

<?php else: ?>

<?php if ($flash): ?>
  <div class="admin-wrap"><div class="success-banner"><?= htmlspecialchars($flash) ?></div></div>
<?php endif; ?>

<div class="section-label">Stored Procedure + Function &mdash; per event</div>
<div class="admin-wrap">
<div class="table-scroll">
<table class="admin-table">
  <tr>
    <th>Event</th>
    <th>Date</th>
    <th>Status</th>
    <th>Revenue (GetEventRevenue)</th>
    <th>Seats left (GetAvailableSeats)</th>
    <th>Action</th>
  </tr>
  <?php foreach ($eventStats as $row): ?>
  <tr>
    <td><?= htmlspecialchars($row['name']) ?></td>
    <td><?= date('d M Y', strtotime($row['event_date'])) ?></td>
    <td><?= htmlspecialchars($row['status']) ?></td>
    <td>Rs. <?= htmlspecialchars($row['revenue']) ?></td>
    <td><?= htmlspecialchars($row['seats']) ?> / <?= (int)$row['capacity'] ?></td>
    <td>
      <form method="POST" class="inline-form">
        <input type="hidden" name="event_id" value="<?= (int)$row['event_id'] ?>">
        <?php if ($row['status'] === 'Cancelled'): ?>
          <button name="action" value="reopen_event" class="btn btn-small">Reopen</button>
        <?php elseif ($row['status'] !== 'Completed'): ?>
          <button name="action" value="cancel_event" class="btn btn-small btn-danger"
                  onclick="return confirm('Cancel this event?');">Cancel event</button>
        <?php endif; ?>
      </form>
    </td>
  </tr>
  <?php endforeach; ?>
</table>
</div>
</div>

<div class="section-label">Registrations &mdash; watch the triggers update these</div>
<div class="admin-wrap">
<div class="table-scroll">
<table class="admin-table">
  <tr><th>#</th><th>Event</th><th>Student</th><th>Email</th><th>Status</th><th>Registered at</th></tr>
  <?php foreach ($registrations as $r): ?>
  <tr>
    <td><?= (int)$r['registration_id'] ?></td>
    <td><?= htmlspecialchars($r['event_name']) ?></td>
    <td><?= htmlspecialchars($r['student']) ?></td>
    <td><?= htmlspecialchars($r['email']) ?></td>
    <td><?= htmlspecialchars($r['status']) ?></td>
    <td><?= htmlspecialchars($r['reg_date']) ?></td>
  </tr>
  <?php endforeach; ?>
</table>
</div>
</div>

<div class="section-label">DCL &mdash; actual privilege grants in effect</div>
<div class="grants-box">
  <?php foreach ($grants as $role => $lines): ?>
    <p class="meta"><?= htmlspecialchars($role) ?>:</p>
    <pre><?php foreach ($lines as $g) echo htmlspecialchars($g) . "\n"; ?></pre>
  <?php endforeach; ?>
</div>

<?php endif; ?>

</body>
</html>
