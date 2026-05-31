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
  p_accuracy DOUBLE PRECISION DEFAULT NULL
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

    v_added_by := 'self | gps:' || round(v_distance::numeric)::TEXT || 'm | acc:' ||
      round(p_accuracy::numeric)::TEXT || 'm | lat:' || round(p_lat::numeric, 6)::TEXT ||
      ' | lng:' || round(p_lng::numeric, 6)::TEXT ||
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

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE absensi ENABLE ROW LEVEL SECURITY;
ALTER TABLE mm_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_all_users" ON users;
DROP POLICY IF EXISTS "allow_all_absensi" ON absensi;
DROP POLICY IF EXISTS "deny_direct_users" ON users;
DROP POLICY IF EXISTS "deny_direct_absensi" ON absensi;
DROP POLICY IF EXISTS "deny_direct_sessions" ON mm_sessions;

CREATE POLICY "deny_direct_users" ON users FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_absensi" ON absensi FOR ALL USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "deny_direct_sessions" ON mm_sessions FOR ALL USING (FALSE) WITH CHECK (FALSE);

REVOKE ALL ON users FROM anon, authenticated;
REVOKE ALL ON absensi FROM anon, authenticated;
REVOKE ALL ON mm_sessions FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_login(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_register(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_me(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_public_counts() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_users(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_absensi(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_submit_absensi(TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_admin_add_absensi(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_delete_absensi(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_update_user_role(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_update_user_name(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_delete_user(TEXT, TEXT) TO anon, authenticated;
