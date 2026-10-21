<?php
declare(strict_types=1);

require dirname(__DIR__) . '/bootstrap.php';
analytics_start_admin_session();
$_SESSION = [];
session_destroy();
header('Location: index.php');
exit;
