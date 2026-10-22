ALTER TABLE logs
    ADD COLUMN IF NOT EXISTS actor_login VARCHAR(100),
    ADD COLUMN IF NOT EXISTS status_log VARCHAR(20) NOT NULL DEFAULT 'Success'
        CHECK (status_log IN ('Success', 'Fail'));

ALTER TABLE logs
    ALTER COLUMN created_at SET DEFAULT NOW();
