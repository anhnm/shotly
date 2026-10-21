<?php
declare(strict_types=1);

require dirname(__DIR__) . '/bootstrap.php';
analytics_require_admin();

$days = max(1, min(365, (int) ($_GET['days'] ?? 30)));
$since = gmdate('Y-m-d H:i:s', time() - ($days * 86400));
$statement = analytics_db()->prepare(
    'SELECT occurred_at, event_name, installation_id, session_id, app_version, macos_version, properties
     FROM analytics_events WHERE occurred_at >= ? ORDER BY occurred_at DESC'
);
$statement->execute([$since]);

header('Content-Type: text/csv; charset=utf-8');
header('Content-Disposition: attachment; filename="shotly-analytics-' . gmdate('Y-m-d') . '.csv"');
header('Cache-Control: no-store');

$output = fopen('php://output', 'wb');
fputcsv($output, ['occurred_at_utc', 'event_name', 'installation_id', 'session_id', 'app_version', 'macos_version', 'properties']);
while ($row = $statement->fetch()) {
    fputcsv($output, $row);
}
fclose($output);
