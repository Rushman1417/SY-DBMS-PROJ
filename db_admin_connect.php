<?php
// Connection for the admin page, using the 'admin_user' role from the
// DCL script (not root). admin_user has full control of this database
// plus read-only access to the mysql schema for SHOW GRANTS.

require_once __DIR__ . '/config.php';

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    $conn = new mysqli(DB_HOST, DB_ADMIN_USER, DB_ADMIN_PASS, DB_NAME);
    $conn->set_charset("utf8mb4");
} catch (mysqli_sql_exception $e) {
    http_response_code(500);
    die("Could not connect to the database as admin_user. "
      . "Check that MySQL is running and that you ran sql/setup_all.sql.");
}
