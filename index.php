<?php
require 'db_connect.php';

$sql = "SELECT e.event_id, e.name, e.event_date, e.start_time, e.capacity, e.status,
               v.name AS venue_name, c.name AS club_name,
               (SELECT COUNT(*) FROM Registrations r
                 WHERE r.event_id = e.event_id AND r.status = 'Confirmed') AS seats_taken
        FROM Events e
        JOIN Venues v ON e.venue_id = v.venue_id
        JOIN Clubs c ON e.club_id = c.club_id
        WHERE e.event_date >= CURDATE()
        ORDER BY e.event_date ASC";
$result = $conn->query($sql);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Campus Events — MIT-WPU</title>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:wght@500;600&family=IBM+Plex+Sans:wght@400;500&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="style.css">
</head>
<body>

<header class="site-header">
  <div class="crest-row">
    <h1>MIT-WPU Campus Events</h1>
    <span class="tagline"><a href="admin.php">Admin: triggers, procedure &amp; DCL demo &rarr;</a></span>
  </div>
</header>

<div class="section-label">Upcoming Events</div>

<div class="events-grid">
<?php if ($result->num_rows === 0): ?>
  <p class="empty-note">No upcoming events right now — check back soon.</p>
<?php endif; ?>

<?php while ($row = $result->fetch_assoc()):
    $seatsLeft = max(0, $row['capacity'] - $row['seats_taken']);

    // Only 'Open' events with a free seat can be registered for.
    // Cancelled/Completed events are closed no matter how many seats are free.
    if ($row['status'] === 'Cancelled') {
        $label = 'Cancelled';  $canRegister = false;
    } elseif ($row['status'] === 'Completed') {
        $label = 'Completed';  $canRegister = false;
    } elseif ($row['status'] === 'Full' || $seatsLeft <= 0) {
        $label = 'Full';       $canRegister = false;
    } else {
        $label = $seatsLeft . ($seatsLeft === 1 ? ' seat left' : ' seats left');
        $canRegister = true;
    }
    $isActive = in_array($row['status'], ['Open', 'Full'], true);
?>
  <div class="ticket<?= $isActive ? '' : ' ticket-closed' ?>">
    <div class="ticket-main">
      <div class="club-tag"><?= htmlspecialchars($row['club_name']) ?></div>
      <h3><?= htmlspecialchars($row['name']) ?></h3>
      <div class="meta">
        <?= date('d M Y', strtotime($row['event_date'])) ?>
        <?php if ($row['start_time']): ?> &middot; <?= date('g:i A', strtotime($row['start_time'])) ?><?php endif; ?>
      </div>
      <div class="meta">@ <?= htmlspecialchars($row['venue_name']) ?></div>

      <span class="status-tag <?= $canRegister ? 'status-open' : 'status-full' ?>"><?= $label ?></span>
      <br>

      <?php if ($canRegister): ?>
        <a class="btn" href="register.php?event_id=<?= (int)$row['event_id'] ?>">Register</a>
      <?php else: ?>
        <span class="btn disabled"><?= $label ?></span>
      <?php endif; ?>

      <?php if ($isActive): ?>
        <a class="text-link" href="cancel.php?event_id=<?= (int)$row['event_id'] ?>">Cancel my registration</a>
      <?php endif; ?>
    </div>
    <div class="ticket-stub"><span>Admit One</span></div>
  </div>
<?php endwhile; ?>
</div>

</body>
</html>
