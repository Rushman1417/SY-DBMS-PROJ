<?php
require 'db_connect.php';

$errors = [];
$success = false;
$registeredName = '';

$event_id = isset($_GET['event_id']) ? (int)$_GET['event_id']
          : (isset($_POST['event_id']) ? (int)$_POST['event_id'] : 0);

// ---- Load the event (also used to show live seat count) ----
function loadEvent(mysqli $conn, int $event_id): ?array {
    $stmt = $conn->prepare(
        "SELECT e.name, e.event_date, e.capacity, e.status, v.name AS venue_name,
                (SELECT COUNT(*) FROM Registrations r
                  WHERE r.event_id = e.event_id AND r.status = 'Confirmed') AS seats_taken
         FROM Events e JOIN Venues v ON e.venue_id = v.venue_id
         WHERE e.event_id = ?"
    );
    $stmt->bind_param("i", $event_id);
    $stmt->execute();
    return $stmt->get_result()->fetch_assoc() ?: null;
}

$event = loadEvent($conn, $event_id);
if (!$event) {
    http_response_code(404);
    die("Event not found. <a href='index.php'>Back to events</a>");
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $email = strtolower(trim($_POST['email'] ?? ''));

    // ---- Server-side validation (never trust the client alone) ----
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $errors[] = "Enter a valid email address.";
    }

    // ---- Find the student through the UserDirectory view ----
    // normal_user can't read the Users table (it holds password hashes),
    // only this view, which exposes user_id, name, email and role.
    $user = null;
    if (empty($errors)) {
        $stmt = $conn->prepare("SELECT user_id, name FROM UserDirectory WHERE email = ?");
        $stmt->bind_param("s", $email);
        $stmt->execute();
        $user = $stmt->get_result()->fetch_assoc();
        if (!$user) {
            $errors[] = "No student account uses that email. Check the spelling, or use the email you registered with.";
        }
    }

    if (empty($errors)) {
        // Does this student already have a row for this event?
        $stmt = $conn->prepare(
            "SELECT registration_id, status FROM Registrations WHERE event_id = ? AND user_id = ?"
        );
        $stmt->bind_param("ii", $event_id, $user['user_id']);
        $stmt->execute();
        $existing = $stmt->get_result()->fetch_assoc();

        try {
            if ($existing && $existing['status'] === 'Confirmed') {
                $errors[] = "You're already registered for this event.";
            } elseif ($existing) {
                // Previously cancelled: re-activate the same row.
                // UNIQUE(event_id, user_id) means we can't insert a second one.
                // trg_prevent_overbooking_on_update guards this path.
                $stmt = $conn->prepare(
                    "UPDATE Registrations SET status = 'Confirmed' WHERE registration_id = ?"
                );
                $stmt->bind_param("i", $existing['registration_id']);
                $stmt->execute();
                $success = true;
            } else {
                // New registration. Guarded at the database level by:
                //  - trg_prevent_overbooking (full or cancelled event)
                //  - UNIQUE(event_id, user_id) (duplicate, e.g. double-click)
                $stmt = $conn->prepare(
                    "INSERT INTO Registrations (event_id, user_id, status) VALUES (?, ?, 'Confirmed')"
                );
                $stmt->bind_param("ii", $event_id, $user['user_id']);
                $stmt->execute();
                $success = true;
            }
            if ($success) {
                $registeredName = $user['name'];
            }
        } catch (mysqli_sql_exception $e) {
            // Translate database errors into messages a student understands
            switch ($e->getCode()) {
                case 1644: // SIGNAL SQLSTATE '45000' from our trigger
                    $errors[] = $e->getMessage();
                    break;
                case 1062: // UNIQUE(event_id, user_id)
                    $errors[] = "You're already registered for this event.";
                    break;
                case 1452: // foreign key failed
                    $errors[] = "That event or student no longer exists.";
                    break;
                default:
                    error_log("register.php: " . $e->getMessage());
                    $errors[] = "Registration couldn't be saved. Try again in a moment.";
            }
        }
    }

    // Reload so the seat count and status reflect what the triggers did
    $event = loadEvent($conn, $event_id);
}

$seatsLeft = max(0, $event['capacity'] - $event['seats_taken']);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Register — <?= htmlspecialchars($event['name']) ?></title>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:wght@500;600&family=IBM+Plex+Sans:wght@400;500&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="style.css">
</head>
<body>

<header class="site-header">
  <div class="crest-row">
    <h1>Event Registration</h1>
    <span class="tagline"><a href="index.php">&larr; back to events</a></span>
  </div>
</header>

<div class="form-card">
  <?php if ($success): ?>
    <div class="success-banner">
      <?= htmlspecialchars($registeredName) ?>, you're registered for <?= htmlspecialchars($event['name']) ?>.
    </div>
  <?php endif; ?>

  <?php if (!empty($errors)): ?>
    <div class="error-banner">
      <?php foreach ($errors as $err): ?>
        <?= htmlspecialchars($err) ?><br>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>

  <h3><?= htmlspecialchars($event['name']) ?></h3>
  <div class="meta">
    <?= date('d M Y', strtotime($event['event_date'])) ?> &middot; <?= htmlspecialchars($event['venue_name']) ?>
  </div>
  <div class="meta">
    Status: <?= htmlspecialchars($event['status']) ?> &middot; <?= $seatsLeft ?> of <?= (int)$event['capacity'] ?> seats left
  </div>

  <?php if (!$success): ?>
  <form method="POST" novalidate>
    <input type="hidden" name="event_id" value="<?= (int)$event_id ?>">

    <label for="email">College email</label>
    <input type="email" id="email" name="email" required placeholder="you@mitwpu.edu.in"
           value="<?= htmlspecialchars($_POST['email'] ?? '') ?>">

    <button type="submit" class="btn">Confirm registration</button>
  </form>
  <?php else: ?>
    <a class="btn" href="index.php">Back to events</a>
  <?php endif; ?>
</div>

<script>
// Client-side validation: mirrors the server check so users get instant
// feedback, but the PHP side above is what actually enforces it.
const form = document.querySelector('form');
if (form) {
  form.addEventListener('submit', function (e) {
    const email = document.getElementById('email').value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      alert('Please enter a valid email address.');
      e.preventDefault();
    }
  });
}
</script>

</body>
</html>
