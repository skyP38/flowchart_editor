ALTER TABLE sessions
    ADD COLUMN device_name TEXT
        NOT NULL DEFAULT 'Unknown device',
    ADD COLUMN location TEXT
        NOT NULL DEFAULT 'Not recorded';
