-- =====================================================================
-- RTSU: схема базы данных (ядро), PostgreSQL 14+
-- Запускать на ПУСТОЙ базе, в DBeaver: "Execute SQL Script" (Alt+X)
-- Все таблицы: uuid PK, created_at/updated_at (timestamptz)
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Расширения и схемы
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS citext;       -- логины без учёта регистра
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- нужен для EXCLUDE (конфликты расписания)

CREATE SCHEMA common;     -- общие функции
CREATE SCHEMA auth;       -- пользователи, роли, права, сессии
CREATE SCHEMA org;        -- структура университета, студенты, преподаватели
CREATE SCHEMA academic;   -- учебный процесс
CREATE SCHEMA schedule;   -- аудитории и расписание

-- Запрет создавать объекты в public для всех
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 1. Общие функции
-- ---------------------------------------------------------------------
CREATE FUNCTION common.set_updated_at() RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- =====================================================================
-- 2. СХЕМА auth
-- =====================================================================
CREATE TABLE auth.users (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    login                citext NOT NULL,
    -- Хэш считает бэкенд (argon2id или bcrypt). Открытый пароль в БД попасть не может.
    password_hash        text   NOT NULL,
    last_name            text   NOT NULL,
    first_name           text   NOT NULL,
    middle_name          text,
    phone                text,
    email                citext,
    photo_path           text,                 -- путь к файлу, а не сам файл
    is_active            boolean NOT NULL DEFAULT true,
    must_change_password boolean NOT NULL DEFAULT true,
    last_login_at        timestamptz,
    deleted_at           timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT users_login_key UNIQUE (login),
    CONSTRAINT users_login_format CHECK (login ~ '^[A-Za-z0-9._-]{3,64}$'),
    CONSTRAINT users_password_hash_format
        CHECK (password_hash ~ '^\$(argon2(id|i|d)|2[aby])\$'),
    CONSTRAINT users_names_not_blank
        CHECK (btrim(last_name) <> '' AND btrim(first_name) <> ''),
    CONSTRAINT users_phone_format CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{7,15}$'),
    CONSTRAINT users_email_format CHECK (email IS NULL OR email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT users_deleted_inactive CHECK (deleted_at IS NULL OR is_active = false)
);
CREATE INDEX users_active_idx ON auth.users (id) WHERE deleted_at IS NULL;

CREATE TABLE auth.roles (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE,
    name        text NOT NULL,
    description text,
    is_system   boolean NOT NULL DEFAULT false,   -- системные роли нельзя удалять
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT roles_code_format CHECK (code ~ '^[a-z][a-z0-9_]{1,49}$')
);

CREATE TABLE auth.permissions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT permissions_code_format CHECK (code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$')
);

CREATE TABLE auth.user_roles (
    user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role_id    uuid NOT NULL REFERENCES auth.roles(id) ON DELETE RESTRICT,
    granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)
);
CREATE INDEX user_roles_role_idx ON auth.user_roles (role_id);

CREATE TABLE auth.role_permissions (
    role_id       uuid NOT NULL REFERENCES auth.roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES auth.permissions(id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX role_permissions_perm_idx ON auth.role_permissions (permission_id);

-- Refresh-токены: в БД только ХЭШ токена (sha256), сам токен хранится у клиента.
-- family_id позволяет при подозрении на кражу отозвать всю цепочку токенов.
CREATE TABLE auth.refresh_sessions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    family_id   uuid NOT NULL DEFAULT gen_random_uuid(),
    token_hash  bytea NOT NULL UNIQUE,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    ip          inet,
    user_agent  text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT refresh_token_hash_len CHECK (octet_length(token_hash) = 32),
    CONSTRAINT refresh_expires_after_create CHECK (expires_at > created_at)
);
CREATE INDEX refresh_sessions_user_idx   ON auth.refresh_sessions (user_id);
CREATE INDEX refresh_sessions_family_idx ON auth.refresh_sessions (family_id);
CREATE INDEX refresh_sessions_expires_idx ON auth.refresh_sessions (expires_at);

-- Проверка права пользователя (используется в триггерах и бэкендом)
CREATE FUNCTION auth.user_has_permission(p_user uuid, p_permission text)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM auth.users u
        JOIN auth.user_roles ur       ON ur.user_id = u.id
        JOIN auth.role_permissions rp ON rp.role_id = ur.role_id
        JOIN auth.permissions p       ON p.id = rp.permission_id
        WHERE u.id = p_user
          AND u.is_active
          AND u.deleted_at IS NULL
          AND p.code = p_permission
    );
$$;

-- Системные роли нельзя удалить или переименовать их код
CREATE FUNCTION auth.protect_system_roles() RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.is_system THEN
        RAISE EXCEPTION 'Системную роль % нельзя удалить', OLD.code;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.is_system AND (NEW.code <> OLD.code OR NEW.is_system = false) THEN
        RAISE EXCEPTION 'Системную роль % нельзя изменить', OLD.code;
    END IF;
    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
CREATE TRIGGER trg_roles_protect BEFORE UPDATE OR DELETE ON auth.roles
    FOR EACH ROW EXECUTE FUNCTION auth.protect_system_roles();

-- =====================================================================
-- 3. СХЕМА org
-- =====================================================================
CREATE TYPE org.student_status AS ENUM ('studying', 'academic_leave', 'expelled', 'graduated');

CREATE TABLE org.faculties (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code       text NOT NULL UNIQUE,
    name       text NOT NULL UNIQUE,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT faculties_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE org.departments (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id uuid NOT NULL REFERENCES org.faculties(id) ON DELETE RESTRICT,
    name       text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT departments_unique_name UNIQUE (faculty_id, name),
    CONSTRAINT departments_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE org.specialties (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id     uuid NOT NULL REFERENCES org.faculties(id) ON DELETE RESTRICT,
    code           text NOT NULL UNIQUE,
    name           text NOT NULL,
    duration_years smallint NOT NULL DEFAULT 4,
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT specialties_unique_name UNIQUE (faculty_id, name),
    CONSTRAINT specialties_duration CHECK (duration_years BETWEEN 1 AND 8)
);
CREATE INDEX specialties_faculty_idx ON org.specialties (faculty_id);

CREATE TABLE org.study_forms (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code       text NOT NULL UNIQUE,
    name       text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE org.financing_types (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code       text NOT NULL UNIQUE,
    name       text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE org.teachers (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,  -- связь 1:1
    department_id uuid NOT NULL REFERENCES org.departments(id) ON DELETE RESTRICT,
    position      text,
    deleted_at    timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX teachers_department_idx ON org.teachers (department_id);

-- Название группы без номера курса (курс меняется каждый год), например "PIA-24"
CREATE TABLE org.groups (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    specialty_id    uuid NOT NULL REFERENCES org.specialties(id) ON DELETE RESTRICT,
    name            text NOT NULL UNIQUE,
    enrollment_year smallint NOT NULL,
    curator_id      uuid REFERENCES org.teachers(id) ON DELETE SET NULL,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT groups_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT groups_year_range CHECK (enrollment_year BETWEEN 1990 AND 2100)
);
CREATE INDEX groups_specialty_idx ON org.groups (specialty_id);
CREATE INDEX groups_curator_idx   ON org.groups (curator_id);

CREATE TABLE org.students (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,  -- связь 1:1
    group_id            uuid NOT NULL REFERENCES org.groups(id) ON DELETE RESTRICT,
    record_book_number  text NOT NULL UNIQUE,
    enrollment_year     smallint NOT NULL,
    study_form_id       uuid NOT NULL REFERENCES org.study_forms(id) ON DELETE RESTRICT,
    financing_type_id   uuid NOT NULL REFERENCES org.financing_types(id) ON DELETE RESTRICT,
    status              org.student_status NOT NULL DEFAULT 'studying',
    deleted_at          timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT students_record_book_format CHECK (record_book_number ~ '^[A-Za-z0-9-]{3,32}$'),
    CONSTRAINT students_year_range CHECK (enrollment_year BETWEEN 1990 AND 2100)
);
CREATE INDEX students_group_idx     ON org.students (group_id);
CREATE INDEX students_study_form_idx ON org.students (study_form_id);
CREATE INDEX students_financing_idx ON org.students (financing_type_id);

-- =====================================================================
-- 4. СХЕМА academic
-- =====================================================================
CREATE TYPE academic.teaching_role AS ENUM ('lecture', 'practice', 'lab', 'seminar');
CREATE TYPE academic.exam_type     AS ENUM ('exam', 'credit', 'coursework');

CREATE TABLE academic.academic_years (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL UNIQUE,                 -- например 2025/2026
    start_date date NOT NULL,
    end_date   date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT academic_years_dates CHECK (end_date > start_date),
    CONSTRAINT academic_years_no_overlap
        EXCLUDE USING gist (daterange(start_date, end_date, '[]') WITH &&)
);

-- term: 1 = осенний, 2 = весенний. Номер семестра группы = (год - год_поступления)*2 + term
CREATE TABLE academic.semesters (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    academic_year_id uuid NOT NULL REFERENCES academic.academic_years(id) ON DELETE RESTRICT,
    term             smallint NOT NULL,
    start_date       date NOT NULL,
    end_date         date NOT NULL,
    is_current       boolean NOT NULL DEFAULT false,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT semesters_unique_term UNIQUE (academic_year_id, term),
    CONSTRAINT semesters_term CHECK (term IN (1, 2)),
    CONSTRAINT semesters_dates CHECK (end_date > start_date),
    CONSTRAINT semesters_no_overlap
        EXCLUDE USING gist (daterange(start_date, end_date, '[]') WITH &&)
);
-- Только один текущий семестр
CREATE UNIQUE INDEX semesters_one_current_idx ON academic.semesters (is_current) WHERE is_current;

CREATE TABLE academic.subjects (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id uuid REFERENCES org.departments(id) ON DELETE SET NULL,
    code          text UNIQUE,
    name          text NOT NULL,
    credits       numeric(4,1) NOT NULL DEFAULT 3,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT subjects_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT subjects_credits CHECK (credits > 0 AND credits <= 30)
);
CREATE INDEX subjects_department_idx ON academic.subjects (department_id);

-- Главная таблица: предмет + группа + семестр
CREATE TABLE academic.course_offerings (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id  uuid NOT NULL REFERENCES academic.subjects(id)  ON DELETE RESTRICT,
    group_id    uuid NOT NULL REFERENCES org.groups(id)         ON DELETE RESTRICT,
    semester_id uuid NOT NULL REFERENCES academic.semesters(id) ON DELETE RESTRICT,
    max_score   numeric(5,2) NOT NULL DEFAULT 100,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT offerings_unique UNIQUE (subject_id, group_id, semester_id),
    CONSTRAINT offerings_id_group_unique UNIQUE (id, group_id),   -- для составных FK
    CONSTRAINT offerings_max_score CHECK (max_score > 0)
);
CREATE INDEX offerings_group_idx    ON academic.course_offerings (group_id);
CREATE INDEX offerings_semester_idx ON academic.course_offerings (semester_id);

CREATE TABLE academic.offering_teachers (
    offering_id uuid NOT NULL REFERENCES academic.course_offerings(id) ON DELETE RESTRICT,
    teacher_id  uuid NOT NULL REFERENCES org.teachers(id)              ON DELETE RESTRICT,
    role        academic.teaching_role NOT NULL DEFAULT 'lecture',
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (offering_id, teacher_id, role)
);
CREATE INDEX offering_teachers_teacher_idx ON academic.offering_teachers (teacher_id);

CREATE TABLE academic.grades (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL REFERENCES academic.course_offerings(id) ON DELETE RESTRICT,
    student_id  uuid NOT NULL REFERENCES org.students(id)              ON DELETE RESTRICT,
    score       numeric(5,2) NOT NULL,
    comment     text,
    graded_by   uuid NOT NULL REFERENCES auth.users(id)                ON DELETE RESTRICT,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT grades_unique UNIQUE (offering_id, student_id),
    CONSTRAINT grades_score_nonneg CHECK (score >= 0)
);
CREATE INDEX grades_student_idx   ON academic.grades (student_id);
CREATE INDEX grades_graded_by_idx ON academic.grades (graded_by);

-- Журнал изменений: только добавление записей (UPDATE/DELETE запрещены триггером)
CREATE TABLE academic.grade_history (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    grade_id    uuid NOT NULL REFERENCES academic.grades(id) ON DELETE RESTRICT,
    operation   text NOT NULL,
    old_score   numeric(5,2),
    new_score   numeric(5,2) NOT NULL,
    old_comment text,
    new_comment text,
    changed_by  uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    changed_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT grade_history_op CHECK (operation IN ('insert', 'update'))
);
CREATE INDEX grade_history_grade_idx ON academic.grade_history (grade_id, changed_at DESC);
CREATE INDEX grade_history_changed_by_idx ON academic.grade_history (changed_by);

-- =====================================================================
-- 5. СХЕМА schedule
-- =====================================================================
CREATE TYPE schedule.lesson_type AS ENUM ('lecture', 'practice', 'lab', 'seminar');

CREATE TABLE schedule.rooms (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    building   text NOT NULL,
    number     text NOT NULL,
    capacity   smallint,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rooms_unique UNIQUE (building, number),
    CONSTRAINT rooms_capacity CHECK (capacity IS NULL OR capacity > 0)
);

-- group_id продублирован из offering и защищён составным FK, чтобы
-- БД сама запрещала пересечение пар у одной группы.
-- week_type: every = каждую неделю, numerator = числитель, denominator = знаменатель
CREATE TABLE schedule.schedule_entries (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL,
    group_id    uuid NOT NULL,
    room_id     uuid REFERENCES schedule.rooms(id) ON DELETE RESTRICT,
    weekday     smallint NOT NULL,
    start_time  time NOT NULL,
    end_time    time NOT NULL,
    lesson_type schedule.lesson_type NOT NULL DEFAULT 'lecture',
    week_type   text NOT NULL DEFAULT 'every',
    week_span   int4range GENERATED ALWAYS AS (
                    CASE week_type
                        WHEN 'numerator'   THEN int4range(1, 2)
                        WHEN 'denominator' THEN int4range(2, 3)
                        ELSE int4range(1, 3)
                    END) STORED,
    time_span   tsrange GENERATED ALWAYS AS (
                    tsrange(DATE '2000-01-01' + start_time, DATE '2000-01-01' + end_time)) STORED,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT entries_offering_fk FOREIGN KEY (offering_id, group_id)
        REFERENCES academic.course_offerings (id, group_id) ON DELETE RESTRICT,
    CONSTRAINT entries_weekday   CHECK (weekday BETWEEN 1 AND 7),
    CONSTRAINT entries_time      CHECK (end_time > start_time),
    CONSTRAINT entries_week_type CHECK (week_type IN ('every', 'numerator', 'denominator')),
    CONSTRAINT entries_room_no_overlap
        EXCLUDE USING gist (room_id WITH =, weekday WITH =, week_span WITH &&, time_span WITH &&)
        WHERE (room_id IS NOT NULL),
    CONSTRAINT entries_group_no_overlap
        EXCLUDE USING gist (group_id WITH =, weekday WITH =, week_span WITH &&, time_span WITH &&)
);
CREATE INDEX entries_offering_idx ON schedule.schedule_entries (offering_id);
CREATE INDEX entries_room_idx     ON schedule.schedule_entries (room_id);

-- Экзамены (в схеме academic, но зависят от rooms, поэтому создаются здесь)
CREATE TABLE academic.exams (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL,
    group_id    uuid NOT NULL,
    room_id     uuid REFERENCES schedule.rooms(id) ON DELETE RESTRICT,
    exam_type   academic.exam_type NOT NULL DEFAULT 'exam',
    exam_date   date NOT NULL,
    start_time  time NOT NULL,
    end_time    time NOT NULL,
    time_span   tsrange GENERATED ALWAYS AS (
                    tsrange(exam_date + start_time, exam_date + end_time)) STORED,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT exams_offering_fk FOREIGN KEY (offering_id, group_id)
        REFERENCES academic.course_offerings (id, group_id) ON DELETE RESTRICT,
    CONSTRAINT exams_unique_type UNIQUE (offering_id, exam_type),
    CONSTRAINT exams_time CHECK (end_time > start_time),
    CONSTRAINT exams_room_no_overlap
        EXCLUDE USING gist (room_id WITH =, time_span WITH &&) WHERE (room_id IS NOT NULL),
    CONSTRAINT exams_group_no_overlap
        EXCLUDE USING gist (group_id WITH =, time_span WITH &&)
);
CREATE INDEX exams_room_idx ON academic.exams (room_id);

-- =====================================================================
-- 6. Триггеры защиты оценок
-- =====================================================================

-- Проверки перед записью оценки:
--  * балл не больше max_score предмета
--  * студент действительно из группы этого предмета и учится
--  * ставить может только преподаватель этого предмета или пользователь
--    с правом grades.write_any
--  * offering_id и student_id менять нельзя
-- Бэкенд обязан в каждой транзакции делать:  SET LOCAL app.user_id = '<uuid>';
CREATE FUNCTION academic.validate_grade() RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_max      numeric;
    v_group    uuid;
    v_st_group uuid;
    v_st_status org.student_status;
    v_actor    uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.offering_id <> OLD.offering_id OR NEW.student_id <> OLD.student_id) THEN
        RAISE EXCEPTION 'Нельзя менять предмет или студента у существующей оценки';
    END IF;

    -- Кто реально выполняет действие (нельзя подделать graded_by)
    v_actor := COALESCE(NULLIF(current_setting('app.user_id', true), '')::uuid, NEW.graded_by);
    NEW.graded_by := v_actor;

    SELECT max_score, group_id INTO v_max, v_group
    FROM academic.course_offerings WHERE id = NEW.offering_id;

    IF NEW.score > v_max THEN
        RAISE EXCEPTION 'Балл % больше максимального (%)', NEW.score, v_max;
    END IF;

    SELECT group_id, status INTO v_st_group, v_st_status
    FROM org.students WHERE id = NEW.student_id AND deleted_at IS NULL;

    IF v_st_group IS DISTINCT FROM v_group THEN
        RAISE EXCEPTION 'Студент не относится к группе этого предмета';
    END IF;
    IF TG_OP = 'INSERT' AND v_st_status <> 'studying' THEN
        RAISE EXCEPTION 'Нельзя ставить оценку студенту со статусом %', v_st_status;
    END IF;

    IF NOT (
        auth.user_has_permission(v_actor, 'grades.write_any')
        OR (
            auth.user_has_permission(v_actor, 'grades.write_own')
            AND EXISTS (
                SELECT 1
                FROM academic.offering_teachers ot
                JOIN org.teachers t ON t.id = ot.teacher_id
                WHERE ot.offering_id = NEW.offering_id
                  AND t.user_id = v_actor
                  AND t.deleted_at IS NULL
            )
        )
    ) THEN
        RAISE EXCEPTION 'Нет права ставить оценку по этому предмету';
    END IF;

    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_grades_validate BEFORE INSERT OR UPDATE ON academic.grades
    FOR EACH ROW EXECUTE FUNCTION academic.validate_grade();

-- Автоматическая запись в журнал
CREATE FUNCTION academic.log_grade_change() RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO academic.grade_history (grade_id, operation, new_score, new_comment, changed_by)
        VALUES (NEW.id, 'insert', NEW.score, NEW.comment, NEW.graded_by);
    ELSIF NEW.score IS DISTINCT FROM OLD.score OR NEW.comment IS DISTINCT FROM OLD.comment THEN
        INSERT INTO academic.grade_history
            (grade_id, operation, old_score, new_score, old_comment, new_comment, changed_by)
        VALUES (NEW.id, 'update', OLD.score, NEW.score, OLD.comment, NEW.comment, NEW.graded_by);
    END IF;
    RETURN NULL;
END;
$$;
CREATE TRIGGER trg_grades_log AFTER INSERT OR UPDATE ON academic.grades
    FOR EACH ROW EXECUTE FUNCTION academic.log_grade_change();

-- Оценки нельзя удалять, журнал нельзя менять и удалять
CREATE FUNCTION academic.forbid_change() RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'Операция % над %.% запрещена', TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;
CREATE TRIGGER trg_grades_no_delete BEFORE DELETE ON academic.grades
    FOR EACH ROW EXECUTE FUNCTION academic.forbid_change();
CREATE TRIGGER trg_grades_no_truncate BEFORE TRUNCATE ON academic.grades
    FOR EACH STATEMENT EXECUTE FUNCTION academic.forbid_change();
CREATE TRIGGER trg_history_immutable BEFORE UPDATE OR DELETE ON academic.grade_history
    FOR EACH ROW EXECUTE FUNCTION academic.forbid_change();
CREATE TRIGGER trg_history_no_truncate BEFORE TRUNCATE ON academic.grade_history
    FOR EACH STATEMENT EXECUTE FUNCTION academic.forbid_change();

-- =====================================================================
-- 7. Автообновление updated_at на всех таблицах
-- =====================================================================
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT table_schema, table_name
        FROM information_schema.columns
        WHERE column_name = 'updated_at'
          AND table_schema IN ('auth', 'org', 'academic', 'schedule')
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON %I.%I
             FOR EACH ROW EXECUTE FUNCTION common.set_updated_at()',
            r.table_name, r.table_schema, r.table_name);
    END LOOP;
END;
$$;

-- =====================================================================
-- 8. Начальные данные (справочники, роли, права)
--    Администратор НЕ создаётся здесь: пароль по умолчанию = дыра.
--    Первого админа создаёт бэкенд через защищённый скрипт.
-- =====================================================================
INSERT INTO org.study_forms (code, name) VALUES
    ('full_time', 'Дневная'),
    ('part_time', 'Заочная');

INSERT INTO org.financing_types (code, name) VALUES
    ('budget',   'Бюджет'),
    ('contract', 'Договор');

INSERT INTO auth.roles (code, name, is_system) VALUES
    ('student', 'Студент',       true),
    ('teacher', 'Преподаватель', true),
    ('admin',   'Администратор', true);

INSERT INTO auth.permissions (code, description) VALUES
    ('schedule.read',    'Просмотр расписания'),
    ('exams.read',       'Просмотр экзаменов'),
    ('grades.read_own',  'Просмотр своих оценок'),
    ('grades.read_any',  'Просмотр любых оценок'),
    ('grades.write_own', 'Ставить оценки по своим предметам'),
    ('grades.write_any', 'Ставить и менять любые оценки'),
    ('users.manage',     'Управление пользователями'),
    ('structure.manage', 'Управление факультетами, группами, предметами'),
    ('schedule.manage',  'Управление расписанием и аудиториями'),
    ('exams.manage',     'Управление экзаменами');

INSERT INTO auth.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM auth.roles r
JOIN auth.permissions p ON p.code IN (
    SELECT unnest(CASE r.code
        WHEN 'student' THEN ARRAY['schedule.read', 'exams.read', 'grades.read_own']
        WHEN 'teacher' THEN ARRAY['schedule.read', 'exams.read', 'grades.write_own']
        WHEN 'admin'   THEN ARRAY['schedule.read', 'exams.read', 'grades.read_own', 'grades.read_any',
                                  'grades.write_own', 'grades.write_any', 'users.manage',
                                  'structure.manage', 'schedule.manage', 'exams.manage']
    END));

COMMIT;
