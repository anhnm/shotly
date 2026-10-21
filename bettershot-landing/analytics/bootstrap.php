<?php
declare(strict_types=1);

function analytics_config(): array
{
    static $config = null;
    if ($config !== null) {
        return $config;
    }

    $path = __DIR__ . '/config.php';
    if (!is_file($path)) {
        throw new RuntimeException('Analytics is not configured. Copy config.example.php to config.php.');
    }

    $config = require $path;
    if (!is_array($config)) {
        throw new RuntimeException('Invalid analytics configuration.');
    }
    return $config;
}

function analytics_db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $database = analytics_config()['database'] ?? [];
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
        $database['host'] ?? 'localhost',
        (int) ($database['port'] ?? 3306),
        $database['name'] ?? ''
    );
    $pdo = new PDO($dsn, $database['user'] ?? '', $database['password'] ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    $pdo->exec("SET time_zone = '+00:00'");
    return $pdo;
}

function analytics_json(int $status, array $body): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function analytics_event_names(): array
{
    return [
        'app_launched',
        'app_first_launch',
        'capture_region',
        'capture_fullscreen',
        'capture_window',
        'color_picker_used',
        'ocr_completed',
        'translation_completed',
        'translation_copied',
        'recording_started',
        'recording_completed',
        'preview_copied',
        'preview_saved',
        'preview_edited',
        'preview_pinned',
        'collage_started',
        'collage_created',
        'editor_tool_used',
        'editor_exported',
    ];
}

function analytics_start_admin_session(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }
    session_name('shotly_analytics_admin');
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
        'httponly' => true,
        'samesite' => 'Strict',
    ]);
    session_start();
}

function analytics_admin_logged_in(): bool
{
    analytics_start_admin_session();
    return ($_SESSION['analytics_admin'] ?? false) === true;
}

function analytics_require_admin(): void
{
    if (!analytics_admin_logged_in()) {
        header('Location: index.php');
        exit;
    }
}

function analytics_csrf_token(): string
{
    analytics_start_admin_session();
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(24));
    }
    return (string) $_SESSION['csrf'];
}

function analytics_verify_csrf(?string $token): bool
{
    return is_string($token) && hash_equals(analytics_csrf_token(), $token);
}

function analytics_h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
