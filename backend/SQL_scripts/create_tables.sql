DROP TABLE IF EXISTS memberships, logs, sessions, flowcharts, projects, groups, users CASCADE;

CREATE TABLE groups (
    id_groups BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name_g VARCHAR(100) NOT NULL UNIQUE,
    date_create TIMESTAMPTZ NOT NULL,
    date_update TIMESTAMPTZ NULL CHECK (date_update >= date_create)
);

CREATE TABLE users (
    id_user BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fio VARCHAR(200) NOT NULL,
    login VARCHAR(100) NOT NULL UNIQUE,
    hash_password VARCHAR(250) NOT NULL,
    status BOOLEAN NOT NULL,
    date_create TIMESTAMPTZ NOT NULL,
    last_login TIMESTAMPTZ  NULL CHECK (last_login >= date_create)
);


CREATE TABLE projects (
    id_project BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name_p VARCHAR(200) NOT NULL,
    id_user BIGINT NOT NULL,
    date_create TIMESTAMPTZ NOT NULL,
    date_update TIMESTAMPTZ NULL CHECK (date_update >= date_create),
    CONSTRAINT fk_projects_user
        FOREIGN KEY (id_user)
		REFERENCES users (id_user)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE flowcharts (
    id_flowchart BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name_f VARCHAR(250) NOT NULL,
    id_project BIGINT NOT NULL,
    data_f JSONB NULL,
    date_create TIMESTAMPTZ NOT NULL,
    date_update TIMESTAMPTZ NULL CHECK (date_update >= date_create),
    CONSTRAINT fk_flowcharts_project
        FOREIGN KEY (id_project)
		REFERENCES projects (id_project)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE sessions (
    id_sessions BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_user BIGINT NOT NULL,
    date_create TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN NOT NULL,
    closing_date TIMESTAMPTZ NULL CHECK (closing_date >= date_create),
    CONSTRAINT fk_sessions_user
        FOREIGN KEY (id_user)
		REFERENCES users (id_user)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE logs (
    id_log BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_user BIGINT,
    action_log VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    entity VARCHAR(100) NULL,
    entity_id BIGINT NULL,
    CONSTRAINT fk_logs_user
        FOREIGN KEY (id_user)
		REFERENCES users (id_user)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE memberships (
    id_group BIGINT NOT NULL,
    id_user  BIGINT NOT NULL,
    CONSTRAINT pk_memberships PRIMARY KEY (id_group, id_user),
    CONSTRAINT fk_memberships_group
        FOREIGN KEY (id_group)
		REFERENCES groups (id_groups)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_memberships_user
        FOREIGN KEY (id_user)
		REFERENCES users (id_user)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);