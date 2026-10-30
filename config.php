<?php
// All database settings in one place.
// These accounts are created by sql/4_event_management_dcl.sql.
// The app never connects as root.

const DB_HOST = "localhost";
const DB_NAME = "event_management_system";

// Public pages (index, register, cancel): restricted student role
const DB_NORMAL_USER = "normal_user";
const DB_NORMAL_PASS = "NormalPass@123";

// Admin page: admin role
const DB_ADMIN_USER = "admin_user";
const DB_ADMIN_PASS = "AdminPass@123";
