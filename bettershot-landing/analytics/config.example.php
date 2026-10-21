<?php
declare(strict_types=1);

// Copy this file to config.php and replace every CHANGE_ME value.
// Keep config.php out of Git. The included .htaccess blocks direct web access.
return [
    'database' => [
        'host' => 'localhost',
        'port' => 3306,
        'name' => 'CHANGE_ME_DATABASE',
        'user' => 'CHANGE_ME_USER',
        'password' => 'CHANGE_ME_PASSWORD',
    ],

    // Sent by Shotly in the X-Shotly-App-Key header. Use a long random value.
    'ingest_key' => 'CHANGE_ME_LONG_RANDOM_INGEST_KEY',

    // Generate with:
    // php -r "echo password_hash('YOUR_ADMIN_PASSWORD', PASSWORD_DEFAULT), PHP_EOL;"
    'admin_password_hash' => 'CHANGE_ME_PASSWORD_HASH',

    // Used only to make short-lived, anonymous rate-limit hashes.
    'rate_limit_salt' => 'CHANGE_ME_DIFFERENT_LONG_RANDOM_VALUE',

    'dashboard_title' => 'Shotly Analytics',
    'timezone' => 'Asia/Ho_Chi_Minh',
];
