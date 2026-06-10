-- MM Visual Showcase safe update
-- Jalankan file ini di Supabase SQL Editor untuk mengaktifkan Featured/Hidden Showcase.
-- Aman untuk data lama: tidak ada DROP, DELETE, atau TRUNCATE.

ALTER TABLE mm_social_posts ADD COLUMN IF NOT EXISTS featured BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE mm_social_posts ADD COLUMN IF NOT EXISTS hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE mm_social_posts ADD COLUMN IF NOT EXISTS showcase_category TEXT DEFAULT '';
ALTER TABLE mm_social_posts ADD COLUMN IF NOT EXISTS featured_by TEXT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE mm_social_posts ADD COLUMN IF NOT EXISTS featured_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION mm_get_social_feed(p_token TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user users;
  v_user_id TEXT := NULL;
  v_is_admin BOOLEAN := FALSE;
BEGIN
  IF COALESCE(TRIM(p_token), '') <> '' THEN
    BEGIN
      v_user := mm_current_user(p_token);
      v_user_id := v_user.id;
      v_is_admin := v_user.role = 'admin';
    EXCEPTION WHEN OTHERS THEN
      v_user_id := NULL;
      v_is_admin := FALSE;
    END;
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'userId', p.user_id,
      'name', p.name,
      'username', p.username,
      'avatarUrl', COALESCE(pc.avatar_url, ''),
      'bio', COALESCE(pc.bio, ''),
      'caption', p.caption,
      'mediaUrl', p.media_url,
      'category', p.media_category,
      'featured', COALESCE(p.featured, FALSE),
      'hidden', COALESCE(p.hidden, FALSE),
      'showcaseCategory', COALESCE(p.showcase_category, ''),
      'createdAt', p.created_at,
      'liked', CASE WHEN v_user_id IS NULL THEN FALSE ELSE EXISTS (SELECT 1 FROM mm_social_likes l WHERE l.post_id = p.id AND l.user_id = v_user_id) END,
      'likes', (SELECT COUNT(*) FROM mm_social_likes l WHERE l.post_id = p.id),
      'shares', (SELECT COUNT(*) FROM mm_social_shares s WHERE s.post_id = p.id),
      'comments', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'username', c.username, 'body', c.body, 'createdAt', c.created_at) ORDER BY c.created_at ASC) FROM mm_social_comments c WHERE c.post_id = p.id), '[]'::jsonb)
    ) ORDER BY p.created_at DESC), '[]'::jsonb)
    FROM mm_social_posts p
    LEFT JOIN mm_profile_custom pc ON pc.user_id = p.user_id
    WHERE v_is_admin OR COALESCE(p.hidden, FALSE) = FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION mm_get_showcase_feed(p_token TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT mm_get_social_feed(p_token);
$$;

CREATE OR REPLACE FUNCTION mm_admin_update_social_post_state(
  p_token TEXT,
  p_post_id UUID,
  p_featured BOOLEAN DEFAULT FALSE,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_category TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin users;
  v_post mm_social_posts;
  v_category TEXT := left(TRIM(COALESCE(p_category, '')), 60);
  v_action TEXT;
BEGIN
  v_admin := mm_current_user(p_token);
  IF v_admin.role <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat mengatur Showcase';
  END IF;

  SELECT * INTO v_post FROM mm_social_posts WHERE id = p_post_id;
  IF v_post.id IS NULL THEN
    RAISE EXCEPTION 'Postingan tidak ditemukan';
  END IF;

  UPDATE mm_social_posts
  SET
    featured = COALESCE(p_featured, FALSE),
    hidden = COALESCE(p_hidden, FALSE),
    showcase_category = CASE WHEN v_category = '' THEN COALESCE(showcase_category, '') ELSE v_category END,
    featured_by = CASE WHEN COALESCE(p_featured, FALSE) THEN v_admin.id ELSE featured_by END,
    featured_at = CASE WHEN COALESCE(p_featured, FALSE) THEN NOW() ELSE featured_at END
  WHERE id = p_post_id;

  v_action := CASE
    WHEN COALESCE(p_hidden, FALSE) THEN 'sembunyikan_postingan'
    WHEN COALESCE(p_featured, FALSE) THEN 'featured_postingan'
    ELSE 'update_showcase_postingan'
  END;

  INSERT INTO mm_admin_audit_logs (admin_id, admin_username, admin_name, action, target_type, target_id, detail)
  VALUES (
    v_admin.id,
    v_admin.username,
    v_admin.name,
    v_action,
    'gallery_post',
    p_post_id::TEXT,
    'featured=' || COALESCE(p_featured, FALSE)::TEXT || ', hidden=' || COALESCE(p_hidden, FALSE)::TEXT || ', category=' || COALESCE(NULLIF(v_category, ''), COALESCE(v_post.media_category, ''))
  );

  RETURN jsonb_build_object('ok', TRUE, 'id', p_post_id, 'featured', COALESCE(p_featured, FALSE), 'hidden', COALESCE(p_hidden, FALSE));
END;
$$;

GRANT EXECUTE ON FUNCTION mm_get_social_feed(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_get_showcase_feed(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mm_admin_update_social_post_state(TEXT, UUID, BOOLEAN, BOOLEAN, TEXT) TO anon, authenticated;
