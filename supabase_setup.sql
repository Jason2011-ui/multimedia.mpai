-- Backend setup untuk website Absensi Multimedia MTs Plus Al Ishlah.
-- Jalankan seluruh file ini di Supabase Dashboard > SQL Editor.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id          TEXT PRIMARY KEY,
  username    TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  password    TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'pengunjung',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS absensi (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  username    TEXT NOT NULL,
  name        TEXT NOT NULL,
  date        TEXT NOT NULL,
  timestamp   BIGINT NOT NULL,
  status      TEXT NOT NULL,
  added_by    TEXT DEFAULT 'self',
  session_id  TEXT
);

CREATE TABLE IF NOT EXISTS mm_sessions (
  id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  token_hash  TEXT UNIQUE NOT NULL,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '14 days'),
  revoked     BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS mm_attendance_grades (
  user_id     TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  grade       TEXT NOT NULL DEFAULT '',
  updated_by  TEXT REFERENCES users(id) ON DELETE SET NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mm_typing_scores (
  id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id     TEXT REFERENCES users(id) ON DELETE CASCADE,
  username    TEXT NOT NULL,
  name        TEXT NOT NULL,
  wpm         INTEGER NOT NULL,
  accuracy    INTEGER NOT NULL,
  correct     INTEGER NOT NULL,
  wrong       INTEGER NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mm_social_posts (
  id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id     TEXT REFERENCES users(id) ON DELETE SET NULL,
  username    TEXT NOT NULL,
  name        TEXT NOT NULL,
  caption     TEXT NOT NULL,
  media_url   TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mm_social_likes (
  post_id     UUID REFERENCES mm_social_posts(id) ON DELETE CASCADE,
  user_id     TEXT REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS mm_social_comments (
  id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  post_id     UUID REFERENCES mm_social_posts(id) ON DELETE CASCADE,
  user_id     TEXT REFERENCES users(id) ON DELETE SET NULL,
  username    TEXT NOT NULL,
  name        TEXT NOT NULL,
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mm_social_shares (
  id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  post_id     UUID REFERENCES mm_social_posts(id) ON DELETE CASCADE,
  user_id     TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mm_daily_qr (
  date        TEXT PRIMARY KEY,
  code        TEXT NOT NULL,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_by  TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

DELETE FROM absensi a
USING absensi b
WHERE a.ctid < b.ctid
  AND a.user_id = b.user_id
  AND a.date = b.date;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'absensi_user_date_unique'
  ) THEN
    ALTER TABLE absensi ADD CONSTRAINT absensi_user_date_unique UNIQUE (user_id, date);
  END IF;
END $$;

INSERT INTO users (id, username, name, password, role)
VALUES ('admin-1', 'admin', 'Administrator', 'hg10hvh8in', 'admin')
ON CONFLICT (id) DO UPDATE
SET username = EXCLUDED.username,
    password = EXCLUDED.password,
    role = EXCLUDED.role;

CREATE OR REPLACE FUNCTION mm_token_hash(p_token TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT encode(extensions.digest(COALESCE(p_token, ''), 'sha256'), 'hex');
$$;

CREATE OR REPLACE FUNCTION mm_distance_m(lat1 DOUBLE PRECISION, lng1 DOUBLE PRECISION, lat2 DOUBLE PRECISION, lng2 DOUBLE PRECISION)
RETURNS DOUBLE PRECISION
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT 6371000 * 2 * asin(
    sqrt(
      power(sin(radians((lat2 - lat1) / 2)), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) *
      power(sin(radians((lng2 - lng1) / 2)), 2)
    )
  );
$$;

CREATE OR REPLACE FUNCTION mm_current_user(p_token TEXT)
RETURNS users
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  SELECT u.*
    INTO v_user
  FROM mm_sessions s
  JOIN users u ON u.id = s.user_id
  WHERE s.token_hash = mm_token_hash(p_token)
    AND s.revoked = FALSE
    AND s.expires_at > NOW()
  LIMIT 1;

  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'Sesi tidak valid atau sudah habis';
  END IF;

  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION mm_user_json(u users)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
  SELECT jsonb_build_object(
    'id', u.id,
    'username', u.username,
    'name', u.name,
    'role', u.role,
    'createdAt', u.created_at
  );
$$;

CREATE OR REPLACE FUNCTION mm_login(p_username TEXT, p_password_hash TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_token TEXT;
BEGIN
  DELETE FROM mm_sessions WHERE expires_at <= NOW() OR revoked = TRUE;

  SELECT *
    INTO v_user
  FROM users
  WHERE LOWER(username) = LOWER(TRIM(p_username))
    AND password = p_password_hash
  LIMIT 1;

  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'Username atau password salah';
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO mm_sessions (token_hash, user_id)
  VALUES (mm_token_hash(v_token), v_user.id);

  RETURN jsonb_build_object(
    'token', v_token,
    'expiresAt', NOW() + INTERVAL '14 days',
    'user', mm_user_json(v_user)
  );
END;
$$;

CREATE OR REPLACE FUNCTION mm_register(p_name TEXT, p_username TEXT, p_password_hash TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  IF LENGTH(TRIM(p_name)) < 3 THEN
    RAISE EXCEPTION 'Nama minimal 3 karakter';
  END IF;

  IF TRIM(p_username) !~ '^[A-Za-z0-9_]{3,30}$' THEN
    RAISE EXCEPTION 'Username hanya huruf, angka, underscore, 3-30 karakter';
  END IF;

  INSERT INTO users (id, username, name, password, role)
  VALUES (
    'u' || replace(extensions.gen_random_uuid()::TEXT, '-', ''),
    LOWER(TRIM(p_username)),
    TRIM(p_name),
    p_password_hash,
    'pengunjung'
  )
  RETURNING * INTO v_user;

  RETURN mm_user_json(v_user);
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Username sudah digunakan';
END;
$$;

CREATE OR REPLACE FUNCTION mm_me(p_token TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  v_user := mm_current_user(p_token);
  RETURN mm_user_json(v_user);
END;
$$;

CREATE OR REPLACE FUNCTION mm_public_counts()
RETURNS JSONB
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'members', (SELECT COUNT(*) FROM users WHERE role IN ('admin', 'anggota')),
    'absensi', (SELECT COUNT(*) FROM absensi)
  );
$$;

CREATE OR REPLACE FUNCTION mm_get_users(p_token TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  v_user := mm_current_user(p_token);

  IF v_user.role <> 'admin' THEN
    RETURN jsonb_build_array(mm_user_json(v_user));
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(mm_user_json(u) ORDER BY u.created_at), '[]'::jsonb)
    FROM users u
  );
END;
$$;

CREATE OR REPLACE FUNCTION mm_get_absensi(p_token TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  v_user := mm_current_user(p_token);

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id,
      'userId', a.user_id,
      'username', a.username,
      'name', a.name,
      'date', a.date,
      'timestamp', a.timestamp,
      'status', a.status,
      'addedBy', a.added_by,
      'sessionId', a.session_id
    ) ORDER BY a.timestamp DESC), '[]'::jsonb)
    FROM absensi a
    WHERE v_user.role = 'admin' OR a.user_id = v_user.id
  );
END;
$$;

CREATE OR REPLACE FUNCTION mm_submit_absensi(
  p_token TEXT,
  p_status TEXT,
  p_note TEXT DEFAULT '',
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
  p_accuracy DOUBLE PRECISION DEFAULT NULL,
  p_qr_code TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_today TEXT := to_char(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM-DD');
  v_now_ms BIGINT := floor(extract(epoch FROM NOW()) * 1000)::BIGINT;
  v_distance DOUBLE PRECISION;
  v_added_by TEXT;
  v_id TEXT := 'ab' || replace(extensions.gen_random_uuid()::TEXT, '-', '');
  v_qr_code TEXT;
BEGIN
  v_user := mm_current_user(p_token);

  IF v_user.role NOT IN ('anggota', 'admin') THEN
    RAISE EXCEPTION 'Akun belum memiliki akses absensi';
  END IF;

  IF p_status NOT IN ('hadir', 'sakit', 'izin') THEN
    RAISE EXCEPTION 'Status absensi tidak valid';
  END IF;

  IF EXISTS (SELECT 1 FROM absensi WHERE user_id = v_user.id AND date = v_today) THEN
    RAISE EXCEPTION 'Anda sudah absen hari ini';
  END IF;

  IF p_status = 'hadir' THEN
    IF p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL THEN
      RAISE EXCEPTION 'Lokasi wajib untuk absen hadir';
    END IF;

    IF p_accuracy > 120 THEN
      RAISE EXCEPTION 'Akurasi GPS belum cukup: % meter', round(p_accuracy::numeric);
    END IF;

    v_distance := mm_distance_m(-6.9818, 107.6432, p_lat, p_lng);

    IF v_distance > 250 THEN
      RAISE EXCEPTION 'Lokasi di luar radius sekolah: % meter', round(v_distance::numeric);
    END IF;

    SELECT code INTO v_qr_code
    FROM mm_daily_qr
    WHERE date = v_today AND active = TRUE
    LIMIT 1;

    IF v_qr_code IS NOT NULL AND TRIM(COALESCE(p_qr_code, '')) <> v_qr_code THEN
      RAISE EXCEPTION 'Kode QR harian tidak valid';
    END IF;

    v_added_by := 'self | gps:' || round(v_distance::numeric)::TEXT || 'm | acc:' ||
      round(p_accuracy::numeric)::TEXT || 'm | lat:' || round(p_lat::numeric, 6)::TEXT ||
      ' | lng:' || round(p_lng::numeric, 6)::TEXT ||
      CASE WHEN v_qr_code IS NOT NULL THEN ' | qr:valid' ELSE '' END ||
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN ' | note:' || left(regexp_replace(TRIM(p_note), '\s+', ' ', 'g'), 220) ELSE '' END ||
      ' | validation:gps-valid-server';
  ELSE
    IF LENGTH(TRIM(COALESCE(p_note, ''))) < 8 THEN
      RAISE EXCEPTION 'Catatan minimal 8 karakter untuk Sakit/Izin';
    END IF;

    v_added_by := 'self | note:' || left(regexp_replace(TRIM(p_note), '\s+', ' ', 'g'), 220) ||
      ' | validation:menunggu-admin';
  END IF;

  INSERT INTO absensi (id, user_id, username, name, date, timestamp, status, added_by, session_id)
  VALUES (v_id, v_user.id, v_user.username, v_user.name, v_today, v_now_ms, p_status, v_added_by, p_token);

  RETURN jsonb_build_object('id', v_id, 'status', p_status, 'date', v_today, 'timestamp', v_now_ms, 'addedBy', v_added_by);
END;
$$;

CREATE OR REPLACE FUNCTION mm_admin_add_absensi(p_token TEXT, p_user_id TEXT, p_date TEXT, p_status TEXT, p_note TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
  v_target users;
  v_id TEXT := 'ab' || replace(extensions.gen_random_uuid()::TEXT, '-', '');
  v_ts BIGINT;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat menambahkan absensi manual';
  END IF;

  IF p_status NOT IN ('hadir', 'sakit', 'izin', 'alfa') THEN
    RAISE EXCEPTION 'Status absensi tidak valid';
  END IF;

  SELECT * INTO v_target FROM users WHERE id = p_user_id LIMIT 1;
  IF v_target.id IS NULL THEN
    RAISE EXCEPTION 'Pengguna tidak ditemukan';
  END IF;

  IF EXISTS (SELECT 1 FROM absensi WHERE user_id = p_user_id AND date = p_date) THEN
    RAISE EXCEPTION 'Pengguna sudah memiliki absensi di tanggal ini';
  END IF;

  v_ts := floor(extract(epoch FROM (p_date::DATE::TIMESTAMP AT TIME ZONE 'Asia/Jakarta')) * 1000)::BIGINT;

  INSERT INTO absensi (id, user_id, username, name, date, timestamp, status, added_by, session_id)
  VALUES (
    v_id,
    v_target.id,
    v_target.username,
    v_target.name,
    p_date,
    v_ts,
    p_status,
    'admin:' || v_admin.username || CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN ' | note:' || left(TRIM(p_note), 220) ELSE '' END || ' | validation:admin-manual',
    NULL
  );

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION mm_delete_absensi(p_token TEXT, p_absensi_id TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat menghapus absensi';
  END IF;

  DELETE FROM absensi WHERE id = p_absensi_id;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION mm_update_user_role(p_token TEXT, p_user_id TEXT, p_role TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat mengubah role';
  END IF;

  IF p_role NOT IN ('admin', 'anggota', 'pengunjung') THEN
    RAISE EXCEPTION 'Role tidak valid';
  END IF;

  UPDATE users SET role = p_role WHERE id = p_user_id;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION mm_update_user_name(p_token TEXT, p_name TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  v_user := mm_current_user(p_token);

  IF LENGTH(TRIM(p_name)) < 3 THEN
    RAISE EXCEPTION 'Nama minimal 3 karakter';
  END IF;

  UPDATE users SET name = TRIM(p_name) WHERE id = v_user.id;
  RETURN jsonb_build_object('ok', TRUE, 'name', TRIM(p_name));
END;
$$;

CREATE OR REPLACE FUNCTION mm_delete_user(p_token TEXT, p_user_id TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat menghapus user';
  END IF;

  IF p_user_id = v_admin.id THEN
    RAISE EXCEPTION 'Admin tidak dapat menghapus akun sendiri';
  END IF;

  DELETE FROM users WHERE id = p_user_id;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION mm_get_grades(p_token TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  v_user := mm_current_user(p_token);
  IF v_user.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat melihat nilai';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_object_agg(user_id, grade), '{}'::jsonb)
    FROM mm_attendance_grades
  );
END;
$$;

CREATE OR REPLACE FUNCTION mm_set_grade(p_token TEXT, p_user_id TEXT, p_grade TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
  v_grade TEXT := left(regexp_replace(TRIM(COALESCE(p_grade, '')), '[^[:alnum:][:space:].,:+-]', '', 'g'), 24);
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat mengisi nilai';
  END IF;

  IF v_grade = '' THEN
    DELETE FROM mm_attendance_grades WHERE user_id = p_user_id;
  ELSE
    INSERT INTO mm_attendance_grades (user_id, grade, updated_by, updated_at)
    VALUES (p_user_id, v_grade, v_admin.id, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET grade = EXCLUDED.grade,
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW();
  END IF;

  RETURN jsonb_build_object('ok', TRUE, 'grade', v_grade);
END;
$$;

CREATE OR REPLACE FUNCTION mm_validate_absensi(p_token TEXT, p_absensi_id TEXT, p_decision TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
  v_suffix TEXT;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat validasi catatan';
  END IF;

  IF p_decision NOT IN ('diterima', 'ditolak') THEN
    RAISE EXCEPTION 'Keputusan validasi tidak valid';
  END IF;

  v_suffix := 'validation:' || p_decision || '-admin:' || v_admin.username;

  UPDATE absensi
  SET added_by = regexp_replace(COALESCE(added_by, ''), '\s*\|\s*validation:[^|]*', '', 'g') || ' | ' || v_suffix
  WHERE id = p_absensi_id;

  RETURN jsonb_build_object('ok', TRUE, 'validation', v_suffix);
END;
$$;

CREATE OR REPLACE FUNCTION mm_submit_typing_score(
  p_token TEXT,
  p_wpm INTEGER,
  p_accuracy INTEGER,
  p_correct INTEGER,
  p_wrong INTEGER
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_id UUID;
BEGIN
  v_user := mm_current_user(p_token);
  IF p_wpm < 0 OR p_accuracy < 0 OR p_accuracy > 100 THEN
    RAISE EXCEPTION 'Skor typing tidak valid';
  END IF;

  INSERT INTO mm_typing_scores (user_id, username, name, wpm, accuracy, correct, wrong)
  VALUES (v_user.id, v_user.username, v_user.name, p_wpm, p_accuracy, p_correct, p_wrong)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION mm_get_typing_leaderboard()
RETURNS JSONB
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'name', name,
    'username', username,
    'wpm', wpm,
    'accuracy', accuracy,
    'correct', correct,
    'wrong', wrong,
    'at', floor(extract(epoch FROM created_at) * 1000)::BIGINT
  ) ORDER BY wpm DESC, accuracy DESC, created_at ASC), '[]'::jsonb)
  FROM (
    SELECT *
    FROM (
      SELECT DISTINCT ON (user_id) *
      FROM mm_typing_scores
      ORDER BY user_id, wpm DESC, accuracy DESC, created_at ASC
    ) best_per_user
    ORDER BY wpm DESC, accuracy DESC, created_at ASC
    LIMIT 10
  ) best;
$$;

CREATE OR REPLACE FUNCTION mm_get_social_feed(p_token TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_user_id TEXT := NULL;
BEGIN
  IF COALESCE(TRIM(p_token), '') <> '' THEN
    BEGIN
      v_user := mm_current_user(p_token);
      v_user_id := v_user.id;
    EXCEPTION WHEN OTHERS THEN
      v_user_id := NULL;
    END;
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'username', p.username,
      'caption', p.caption,
      'mediaUrl', p.media_url,
      'createdAt', p.created_at,
      'liked', CASE WHEN v_user_id IS NULL THEN FALSE ELSE EXISTS (SELECT 1 FROM mm_social_likes l WHERE l.post_id = p.id AND l.user_id = v_user_id) END,
      'likes', (SELECT COUNT(*) FROM mm_social_likes l WHERE l.post_id = p.id),
      'shares', (SELECT COUNT(*) FROM mm_social_shares s WHERE s.post_id = p.id),
      'comments', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'username', c.username, 'body', c.body, 'createdAt', c.created_at) ORDER BY c.created_at ASC) FROM mm_social_comments c WHERE c.post_id = p.id), '[]'::jsonb)
    ) ORDER BY p.created_at DESC), '[]'::jsonb)
    FROM mm_social_posts p
  );
END;
$$;

CREATE OR REPLACE FUNCTION mm_create_social_post(p_token TEXT, p_caption TEXT, p_media_url TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_id UUID;
BEGIN
  v_user := mm_current_user(p_token);
  IF v_user.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat membuat posting sosial';
  END IF;

  IF LENGTH(TRIM(p_caption)) < 3 THEN
    RAISE EXCEPTION 'Caption minimal 3 karakter';
  END IF;

  INSERT INTO mm_social_posts (user_id, username, name, caption, media_url)
  VALUES (v_user.id, v_user.username, v_user.name, left(TRIM(p_caption), 700), NULLIF(TRIM(p_media_url), ''))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION mm_delete_social_post(p_token TEXT, p_post_id UUID)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat menghapus posting sosial';
  END IF;

  DELETE FROM mm_social_posts WHERE id = p_post_id;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION mm_toggle_social_like(p_token TEXT, p_post_id UUID)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_liked BOOLEAN;
BEGIN
  v_user := mm_current_user(p_token);
  IF EXISTS (SELECT 1 FROM mm_social_likes WHERE post_id = p_post_id AND user_id = v_user.id) THEN
    DELETE FROM mm_social_likes WHERE post_id = p_post_id AND user_id = v_user.id;
    v_liked := FALSE;
  ELSE
    INSERT INTO mm_social_likes (post_id, user_id) VALUES (p_post_id, v_user.id);
    v_liked := TRUE;
  END IF;
  RETURN jsonb_build_object('liked', v_liked);
END;
$$;

CREATE OR REPLACE FUNCTION mm_add_social_comment(p_token TEXT, p_post_id UUID, p_body TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_id UUID;
BEGIN
  v_user := mm_current_user(p_token);
  IF LENGTH(TRIM(p_body)) < 2 THEN
    RAISE EXCEPTION 'Komentar terlalu pendek';
  END IF;

  INSERT INTO mm_social_comments (post_id, user_id, username, name, body)
  VALUES (p_post_id, v_user.id, v_user.username, v_user.name, left(TRIM(p_body), 240))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION mm_add_social_share(p_token TEXT, p_post_id UUID)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
BEGIN
  v_user := mm_current_user(p_token);
  INSERT INTO mm_social_shares (post_id, user_id) VALUES (p_post_id, v_user.id);
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION mm_admin_set_daily_qr(p_token TEXT, p_code TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
  v_today TEXT := to_char(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM-DD');
  v_code TEXT := upper(COALESCE(NULLIF(TRIM(p_code), ''), substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 8)));
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat membuat kode QR harian';
  END IF;

  INSERT INTO mm_daily_qr (date, code, active, created_by, created_at)
  VALUES (v_today, v_code, TRUE, v_admin.id, NOW())
  ON CONFLICT (date) DO UPDATE
  SET code = EXCLUDED.code, active = TRUE, created_by = EXCLUDED.created_by, created_at = NOW();

  RETURN jsonb_build_object('date', v_today, 'code', v_code);
END;
$$;

CREATE OR REPLACE FUNCTION mm_get_daily_qr(p_token TEXT)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
  v_today TEXT := to_char(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM-DD');
  v_row mm_daily_qr;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat melihat kode QR';
  END IF;

  SELECT * INTO v_row FROM mm_daily_qr WHERE date = v_today LIMIT 1;
  RETURN jsonb_build_object('date', v_today, 'code', v_row.code, 'active', COALESCE(v_row.active, FALSE));
END;
$$;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE absensi ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_attendance_grades ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_typing_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_social_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_social_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_social_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_social_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_daily_qr ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_all_users" ON users;
DROP POLICY IF EXISTS "allow_all_absensi" ON absensi;
DROP POLICY IF EXISTS "deny_direct_users" ON users;
DROP POLICY IF EXISTS "deny_direct_absensi" ON absensi;
DROP POLICY IF EXISTS "deny_direct_sessions" ON mm_sessions;
DROP POLICY IF EXISTS "deny_direct_grades" ON mm_attendance_grades;
DROP POLICY IF EXISTS "deny_direct_typing" ON mm_typing_scores;
DROP POLICY IF EXISTS "deny_direct_social_posts" ON mm_social_posts;
DROP POLICY IF EXISTS "deny_direct_social_likes" ON mm_social_likes;
DROP POLICY IF EXISTS "deny_direct_social_comments" ON mm_social_comments;
DROP POLICY IF EXISTS "deny_direct_social_shares" ON mm_social_shares;
DROP POLICY IF EXISTS "deny_direct_daily_qr" ON mm_daily_qr;

CREATE POLICY "deny_direct_users" ON users FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_absensi" ON absensi FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_sessions" ON mm_sessions FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_grades" ON mm_attendance_grades FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_typing" ON mm_typing_scores FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_social_posts" ON mm_social_posts FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_social_likes" ON mm_social_likes FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_social_comments" ON mm_social_comments FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_social_shares" ON mm_social_shares FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_daily_qr" ON mm_daily_qr FOR ALL USING (FALSE) WITH CHECK (FALSE);

REVOKE ALL ON users FROM anon, authenticated;
REVOKE ALL ON absensi FROM anon, authenticated;
REVOKE ALL ON mm_sessions FROM anon, authenticated;
REVOKE ALL ON mm_attendance_grades FROM anon, authenticated;
REVOKE ALL ON mm_typing_scores FROM anon, authenticated;
REVOKE ALL ON mm_social_posts FROM anon, authenticated;
REVOKE ALL ON mm_social_likes FROM anon, authenticated;
REVOKE ALL ON mm_social_comments FROM anon, authenticated;
REVOKE ALL ON mm_social_shares FROM anon, authenticated;
REVOKE ALL ON mm_daily_qr FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_login(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_register(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_me(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_public_counts() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_users(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_absensi(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_submit_absensi(TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_admin_add_absensi(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_delete_absensi(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_update_user_role(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_update_user_name(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_delete_user(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_grades(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_set_grade(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_validate_absensi(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_submit_typing_score(TEXT, INTEGER, INTEGER, INTEGER, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_typing_leaderboard() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_social_feed(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_create_social_post(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_delete_social_post(TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_toggle_social_like(TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_add_social_comment(TEXT, UUID, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_add_social_share(TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_admin_set_daily_qr(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_daily_qr(TEXT) TO anon, authenticated;
