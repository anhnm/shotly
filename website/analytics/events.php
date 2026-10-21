<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        header('Allow: POST');
        analytics_json(405, ['ok' => false, 'error' => 'POST required']);
    }

    $config = analytics_config();
    $providedKey = $_SERVER['HTTP_X_SHOTLY_APP_KEY'] ?? '';
    if (!is_string($providedKey) || !hash_equals((string) ($config['ingest_key'] ?? ''), $providedKey)) {
        analytics_json(401, ['ok' => false, 'error' => 'Invalid app key']);
    }

    $contentLength = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($contentLength > 262144) {
        analytics_json(413, ['ok' => false, 'error' => 'Payload too large']);
    }

    $body = json_decode((string) file_get_contents('php://input'), true, 32, JSON_THROW_ON_ERROR);
    $events = $body['events'] ?? null;
    if (!is_array($events) || count($events) < 1 || count($events) > 50) {
        analytics_json(422, ['ok' => false, 'error' => 'events must contain 1 to 50 items']);
    }

    $pdo = analytics_db();
    $remoteAddress = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
    $rateKey = hash_hmac('sha256', $remoteAddress, (string) ($config['rate_limit_salt'] ?? ''));
    $minuteBucket = gmdate('Y-m-d H:i:00');

    $pdo->beginTransaction();
    $rate = $pdo->prepare(
        'INSERT INTO analytics_rate_limits (rate_key, minute_bucket, event_count)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE event_count = event_count + VALUES(event_count)'
    );
    $rate->execute([$rateKey, $minuteBucket, count($events)]);
    $checkRate = $pdo->prepare('SELECT event_count FROM analytics_rate_limits WHERE rate_key = ? AND minute_bucket = ?');
    $checkRate->execute([$rateKey, $minuteBucket]);
    if ((int) $checkRate->fetchColumn() > 300) {
        $pdo->rollBack();
        analytics_json(429, ['ok' => false, 'error' => 'Rate limit exceeded']);
    }

    $allowedNames = array_flip(analytics_event_names());
    $uuidPattern = '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i';
    $insert = $pdo->prepare(
        'INSERT INTO analytics_events
         (installation_id, session_id, event_name, app_version, macos_version, properties, occurred_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );

    $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
    foreach ($events as $event) {
        if (!is_array($event)) {
            throw new InvalidArgumentException('Invalid event');
        }

        $name = (string) ($event['name'] ?? '');
        $installationID = (string) ($event['installation_id'] ?? '');
        $sessionID = (string) ($event['session_id'] ?? '');
        if (!isset($allowedNames[$name]) || !preg_match($uuidPattern, $installationID) || !preg_match($uuidPattern, $sessionID)) {
            throw new InvalidArgumentException('Invalid event identity');
        }

        $properties = $event['properties'] ?? [];
        if (!is_array($properties) || count($properties) > 12) {
            throw new InvalidArgumentException('Invalid properties');
        }
        $cleanProperties = [];
        foreach ($properties as $key => $value) {
            if (!is_string($key) || !preg_match('/^[a-z][a-z0-9_]{0,31}$/', $key)) {
                continue;
            }
            if (is_bool($value) || is_int($value) || is_float($value)) {
                $cleanProperties[$key] = $value;
            } elseif (is_string($value)) {
                $cleanProperties[$key] = mb_substr($value, 0, 100);
            }
        }

        try {
            $occurredAt = new DateTimeImmutable((string) ($event['occurred_at'] ?? ''), new DateTimeZone('UTC'));
        } catch (Throwable) {
            $occurredAt = $now;
        }
        if (abs($occurredAt->getTimestamp() - $now->getTimestamp()) > 604800) {
            $occurredAt = $now;
        }

        $insert->execute([
            strtolower($installationID),
            strtolower($sessionID),
            $name,
            mb_substr((string) ($event['app_version'] ?? 'unknown'), 0, 32),
            mb_substr((string) ($event['macos_version'] ?? 'unknown'), 0, 32),
            json_encode($cleanProperties, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
            $occurredAt->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s.v'),
        ]);
    }

    $pdo->commit();
    if (random_int(1, 100) === 1) {
        $pdo->exec('DELETE FROM analytics_rate_limits WHERE minute_bucket < UTC_TIMESTAMP() - INTERVAL 1 DAY');
    }
    analytics_json(202, ['ok' => true, 'accepted' => count($events)]);
} catch (JsonException | InvalidArgumentException $error) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    analytics_json(422, ['ok' => false, 'error' => $error->getMessage()]);
} catch (Throwable $error) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('Shotly analytics: ' . $error->getMessage());
    analytics_json(500, ['ok' => false, 'error' => 'Server error']);
}
