<?php
declare(strict_types=1);

require dirname(__DIR__) . '/bootstrap.php';

$config = analytics_config();
$error = null;
analytics_start_admin_session();

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['password'])) {
    if (!analytics_verify_csrf($_POST['csrf'] ?? null)) {
        $error = 'Session expired. Please try again.';
    } elseif (password_verify((string) $_POST['password'], (string) ($config['admin_password_hash'] ?? ''))) {
        session_regenerate_id(true);
        $_SESSION['analytics_admin'] = true;
        header('Location: index.php');
        exit;
    } else {
        $error = 'Incorrect password.';
    }
}

$loggedIn = analytics_admin_logged_in();
$days = max(1, min(365, (int) ($_GET['days'] ?? 30)));
$summary = [];
$topEvents = [];
$topTools = [];
$daily = [];

if ($loggedIn) {
    $pdo = analytics_db();
    $since = gmdate('Y-m-d H:i:s', time() - ($days * 86400));

    $statement = $pdo->prepare(
        'SELECT COUNT(*) AS events,
                COUNT(DISTINCT installation_id) AS installations,
                COUNT(DISTINCT CASE WHEN occurred_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY THEN installation_id END) AS dau,
                COUNT(DISTINCT CASE WHEN occurred_at >= UTC_TIMESTAMP() - INTERVAL 7 DAY THEN installation_id END) AS wau
         FROM analytics_events WHERE occurred_at >= ?'
    );
    $statement->execute([$since]);
    $summary = $statement->fetch() ?: [];

    $statement = $pdo->prepare(
        'SELECT event_name, COUNT(*) AS total, COUNT(DISTINCT installation_id) AS users
         FROM analytics_events WHERE occurred_at >= ?
         GROUP BY event_name ORDER BY total DESC LIMIT 15'
    );
    $statement->execute([$since]);
    $topEvents = $statement->fetchAll();

    $statement = $pdo->prepare(
        "SELECT JSON_UNQUOTE(JSON_EXTRACT(properties, '$.tool')) AS tool,
                COUNT(*) AS total, COUNT(DISTINCT installation_id) AS users
         FROM analytics_events
         WHERE occurred_at >= ? AND event_name = 'editor_tool_used'
               AND JSON_EXTRACT(properties, '$.tool') IS NOT NULL
         GROUP BY tool ORDER BY total DESC LIMIT 15"
    );
    $statement->execute([$since]);
    $topTools = $statement->fetchAll();

    $statement = $pdo->prepare(
        'SELECT DATE(occurred_at) AS day, COUNT(DISTINCT installation_id) AS users, COUNT(*) AS events
         FROM analytics_events WHERE occurred_at >= ?
         GROUP BY DATE(occurred_at) ORDER BY day ASC'
    );
    $statement->execute([$since]);
    $daily = $statement->fetchAll();
}

$maxDaily = max(array_map(static fn(array $row): int => (int) $row['events'], $daily) ?: [1]);
$title = (string) ($config['dashboard_title'] ?? 'Shotly Analytics');
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex,nofollow">
    <title><?= analytics_h($title) ?></title>
    <style>
        :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:#111315; color:#f5f5f5; }
        * { box-sizing:border-box; } body { margin:0; } a { color:inherit; }
        .shell { width:min(1120px, calc(100% - 32px)); margin:0 auto; padding:40px 0 64px; }
        .top { display:flex; align-items:center; justify-content:space-between; gap:16px; margin-bottom:28px; }
        h1,h2,p { margin-top:0; } h1 { font-size:28px; margin-bottom:4px; } h2 { font-size:17px; }
        .muted { color:#9da3aa; } .card { background:#1b1e21; border:1px solid #30343a; border-radius:14px; padding:20px; }
        .metrics { display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin-bottom:12px; }
        .metric strong { display:block; font-size:30px; font-variant-numeric:tabular-nums; margin-top:8px; }
        .grid { display:grid; grid-template-columns:1.2fr .8fr; gap:12px; margin-top:12px; }
        table { width:100%; border-collapse:collapse; } th,td { text-align:left; padding:10px 8px; border-bottom:1px solid #2a2e33; font-variant-numeric:tabular-nums; }
        th { color:#9da3aa; font-size:12px; } td:nth-child(n+2), th:nth-child(n+2) { text-align:right; }
        .button,button,select,input { border:1px solid #3b4047; border-radius:9px; background:#25292e; color:#fff; padding:9px 12px; font:inherit; }
        .button { text-decoration:none; display:inline-block; } button { cursor:pointer; background:#1478ff; border-color:#1478ff; }
        .actions { display:flex; align-items:center; gap:8px; } .chart { display:flex; align-items:flex-end; gap:4px; height:190px; padding-top:16px; overflow:hidden; }
        .bar { flex:1; min-width:4px; background:#1478ff; border-radius:4px 4px 0 0; opacity:.82; }
        .login { width:min(420px, calc(100% - 32px)); margin:12vh auto; } label { display:block; margin-bottom:8px; }
        input[type=password] { width:100%; margin-bottom:12px; } .error { color:#ff7777; }
        @media (max-width:800px) { .metrics { grid-template-columns:repeat(2,1fr); } .grid { grid-template-columns:1fr; } .top { align-items:flex-start; flex-direction:column; } }
    </style>
</head>
<body>
<?php if (!$loggedIn): ?>
    <main class="login card">
        <h1><?= analytics_h($title) ?></h1>
        <p class="muted">Private dashboard</p>
        <?php if ($error): ?><p class="error"><?= analytics_h($error) ?></p><?php endif; ?>
        <form method="post">
            <input type="hidden" name="csrf" value="<?= analytics_h(analytics_csrf_token()) ?>">
            <label for="password">Password</label>
            <input id="password" name="password" type="password" autocomplete="current-password" required autofocus>
            <button type="submit">Sign in</button>
        </form>
    </main>
<?php else: ?>
    <main class="shell">
        <header class="top">
            <div><h1><?= analytics_h($title) ?></h1><div class="muted">Anonymous product usage, last <?= $days ?> days</div></div>
            <div class="actions">
                <form method="get"><select name="days" onchange="this.form.submit()" aria-label="Date range">
                    <?php foreach ([7,30,90,365] as $option): ?><option value="<?= $option ?>" <?= $days === $option ? 'selected' : '' ?>><?= $option ?> days</option><?php endforeach; ?>
                </select></form>
                <a class="button" href="export.php?days=<?= $days ?>">Export CSV</a>
                <a class="button" href="logout.php">Log out</a>
            </div>
        </header>
        <section class="metrics">
            <article class="card metric"><span class="muted">Installations</span><strong><?= number_format((int)($summary['installations'] ?? 0)) ?></strong></article>
            <article class="card metric"><span class="muted">Events</span><strong><?= number_format((int)($summary['events'] ?? 0)) ?></strong></article>
            <article class="card metric"><span class="muted">Daily active</span><strong><?= number_format((int)($summary['dau'] ?? 0)) ?></strong></article>
            <article class="card metric"><span class="muted">Weekly active</span><strong><?= number_format((int)($summary['wau'] ?? 0)) ?></strong></article>
        </section>
        <section class="card">
            <h2>Activity</h2>
            <?php if (!$daily): ?><p class="muted">No events in this period.</p><?php else: ?>
                <div class="chart" aria-label="Daily event chart">
                    <?php foreach ($daily as $row): $height = max(3, ((int)$row['events'] / $maxDaily) * 100); ?>
                        <div class="bar" style="height:<?= number_format($height, 2, '.', '') ?>%" title="<?= analytics_h($row['day']) ?>: <?= (int)$row['events'] ?> events, <?= (int)$row['users'] ?> users"></div>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
        <section class="grid">
            <article class="card"><h2>Top features</h2><table><thead><tr><th>Event</th><th>Uses</th><th>Users</th></tr></thead><tbody>
                <?php foreach ($topEvents as $row): ?><tr><td><?= analytics_h($row['event_name']) ?></td><td><?= number_format((int)$row['total']) ?></td><td><?= number_format((int)$row['users']) ?></td></tr><?php endforeach; ?>
            </tbody></table></article>
            <article class="card"><h2>Editor tools</h2><table><thead><tr><th>Tool</th><th>Uses</th><th>Users</th></tr></thead><tbody>
                <?php foreach ($topTools as $row): ?><tr><td><?= analytics_h((string)$row['tool']) ?></td><td><?= number_format((int)$row['total']) ?></td><td><?= number_format((int)$row['users']) ?></td></tr><?php endforeach; ?>
            </tbody></table></article>
        </section>
    </main>
<?php endif; ?>
</body>
</html>
