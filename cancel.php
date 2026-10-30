<?php
require 'db_connect.php';

$errors = [];
$success = false;

$event_id = isset($_GET['event_id']) ? (int)$_GET['event_id']
          : (isset($_POST['event_id']) ? (int)$_POST['event_id'] : 0);

$stmt = $conn->prepare(
    "SELECT e.name, e.event_date, v.name AS venue_name
     FROM Events e JOIN Venues v ON e.venue_id = v.venue_id
     WHERE e.event_id = ?"
);
$stmt->bind_param("i", $event_id);
$stmt->execute();
$event = $stmt->get_result()->fetch_assoc();

if (!$event) {
    http_response_code(404);
    die("Event not found. <a href='index.php'>Back to events</a>");
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $email = strtolower(trim($_POST['email'] ?? ''));

    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $errors[] = "Enter a valid email address.";
    } else {
        $stmt = $conn->prepare("SELECT user_id FROM UserDirectory WHERE email = ?");
        $stmt->bind_param("s", $email);
        $stmt->execute();
        $user = $stmt->get_result()->fetch_assoc();

        if (!$user) {
            $errors[] = "No student account uses that email.";
        } else {
            // A cancellation is an UPDATE of the status column, not a DELETE:
            //  - normal_user has no DELETE privilege (revoked in the DCL)
            //  - normal_user can only UPDATE the status column
            //  - the row is kept, so there's a record of the cancellation
            // The WHERE clause ties the change to this student's own row, and
            // trg_sync_status_on_update flips a 'Full' event back to 'Open'.
            $stmt = $conn->prepare(
                "UPDATE Registrations SET status = 'Cancelled'
                 WHERE event_id = ? AND user_id = ? AND status = 'Confirmed'"
            );
            $stmt->bind_param("ii", $event_id, $user['user_id']);
            $stmt->execute();

            if ($stmt->affected_rows === 1) {
                $success = true;
            } else {
                $errors[] = "That email has no active registration for this event.";
            }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cancel registration — <?= htmlspecialchars($event['name']) ?></title>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:wght@500;600&family=IBM+Plex+Sans:wght@400;500&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="style.css">
</head>
<body>

<header class="site-header">
  <div class="crest-row">
    <h1>Cancel Registration</h1>
    <span class="tagline"><a href="index.php">&larr; back to events</a></span>
  </div>
</header>

<div class="form-card">
  <?php if ($success): ?>
    <div class="success-banner">Your registration for <?= htmlspecialchars($event['name']) ?> is cancelled and your seat has been released.</div>
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

  <?php if (!$success): ?>
  <form method="POST">
    <input type="hidden" name="event_id" value="<?= (int)$event_id ?>">

    <label for="email">College email you registered with</label>
    <input type="email" id="email" name="email" required placeholder="you@mitwpu.edu.in"
           value="<?= htmlspecialchars($_POST['email'] ?? '') ?>">

    <button type="submit" class="btn btn-danger">Cancel registration</button>
  </form>
  <?php else: ?>
    <a class="btn" href="index.php">Back to events</a>
  <?php endif; ?>
</div>

</body>
</html>
