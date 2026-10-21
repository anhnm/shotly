CREATE TABLE IF NOT EXISTS analytics_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    installation_id CHAR(36) NOT NULL,
    session_id CHAR(36) NOT NULL,
    event_name VARCHAR(64) NOT NULL,
    app_version VARCHAR(32) NOT NULL,
    macos_version VARCHAR(32) NOT NULL,
    properties JSON NULL,
    occurred_at DATETIME(3) NOT NULL,
    received_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    INDEX idx_events_occurred (occurred_at),
    INDEX idx_events_name_occurred (event_name, occurred_at),
    INDEX idx_events_installation_occurred (installation_id, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analytics_rate_limits (
    rate_key CHAR(64) NOT NULL,
    minute_bucket DATETIME NOT NULL,
    event_count SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (rate_key, minute_bucket),
    INDEX idx_rate_bucket (minute_bucket)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
