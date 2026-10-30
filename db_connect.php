<?php
// Connection for the public pages, using the restricted 'normal_user'
// role from the DCL script, so the app itself can't do anything the
// role wasn't granted (no reading Users or Payments, no DELETE, and
// UPDATE only on Registrations.status).

require_once __DIR__ . '/config.php';

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT); // exceptions instead of silent failures

try {
    $conn = new mysqli(DB_HOST, DB_NORMAL_USER, DB_NORMAL_PASS, DB_NAME);
    $conn->set_charset("utf8mb4");
} catch (mysqli_sql_exception $e) {
    http_response_code(500);
    die("Could not connect to the database as normal_user. "
      . "Check that MySQL is running and that you ran sql/setup_all.sql.");
}
