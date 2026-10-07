DROP TABLE IF EXISTS logs, sessions, flowcharts, projects, users CASCADE;

CREATE TABLE users (
    id_user BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uname VARCHAR(200) NOT NULL,
    login VARCHAR(100) NOT NULL UNIQUE,
	role VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    hash_password VARCHAR(250) NOT NULL,
    status BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    last_login TIMESTAMPTZ  NULL CHECK (last_login >= created_at),
	is_active BOOLEAN NOT NULL DEFAULT TRUE
);


CREATE TABLE projects (
    id_project BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name_p VARCHAR(200) NOT NULL,
    owner_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NULL CHECK (updated_at >= created_at),
    CONSTRAINT fk_projects_user
        FOREIGN KEY (owner_id)
		REFERENCES users (owner_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE flowcharts (
    id_flowchart BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name_f VARCHAR(250) NOT NULL,
    id_project BIGINT NOT NULL,
    data_f JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NULL CHECK (updated_at >= created_at),
    CONSTRAINT fk_flowcharts_project
        FOREIGN KEY (id_project)
		REFERENCES projects (id_project)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE sessions (
    id_sessions BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_user BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
	expires_at TIMESTAMPTZ NOT NULL,
	revoked_at TIMESTAMPTZ NULL,
	token_hash VARCHAR(64) NOT NULL UNIQUE
    CONSTRAINT fk_sessions_user
        FOREIGN KEY (id_user)
		REFERENCES users (id_user)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
