CREATE OR REPLACE FUNCTION public.mark_cannot_attend(
  p_application_id uuid
)
RETURNS TABLE(
  id uuid,
  status text,
  cannot_attend_at timestamptz,
  scheduled_at timestamptz,
  study_id uuid,
  contributor_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app record;
  v_updated record;
  v_study record;
  v_contributor_name text;
  v_date_text text;
BEGIN
  SELECT a.*
    INTO v_app
    FROM public.applications a
   WHERE a.id = p_application_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application is not scheduled';
  END IF;

  IF v_app.contributor_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Application is not scheduled';
  END IF;

  IF v_app.status <> 'accepted' OR v_app.scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Application is not scheduled';
  END IF;

  UPDATE public.applications a
     SET status = 'cannot_attend',
         cannot_attend_at = now(),
         updated_at = now()
   WHERE a.id = p_application_id
     AND a.status = 'accepted'
     AND a.scheduled_at IS NOT NULL
   RETURNING a.id, a.status, a.cannot_attend_at, a.scheduled_at, a.study_id, a.contributor_id
        INTO v_updated;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application is not scheduled';
  END IF;

  SELECT s.id, s.title, s.created_by
    INTO v_study
    FROM public.studies s
   WHERE s.id = v_updated.study_id;

  SELECT COALESCE(NULLIF(trim(COALESCE(p.first_name, '') || ' ' || COALESCE(p.last_name, '')), ''), 'A contributor')
    INTO v_contributor_name
    FROM public.profiles p
   WHERE p.id = v_updated.contributor_id;

  v_contributor_name := COALESCE(v_contributor_name, 'A contributor');
  v_date_text := to_char(v_updated.scheduled_at, 'Dy, Mon DD HH24:MI');

  IF v_study.created_by IS NOT NULL THEN
    PERFORM public.insert_notification(
      v_study.created_by,
      'Contributor can''t attend',
      v_contributor_name || ' can''t attend their session for "' || COALESCE(v_study.title, 'this study') || '" on ' || v_date_text || '.',
      CASE WHEN v_updated.study_id IS NOT NULL THEN '#applicants/' || v_updated.study_id::text || '/' || COALESCE(v_study.title, '') ELSE NULL END,
      'cant_attend',
      jsonb_build_object(
        'study_id', v_updated.study_id,
        'application_id', v_updated.id,
        'contributor_id', v_updated.contributor_id,
        'scheduled_at', v_updated.scheduled_at,
        'name', v_contributor_name,
        'title', COALESCE(v_study.title, 'this study'),
        'date', v_date_text
      )
    );
  END IF;

  RETURN QUERY
  SELECT v_updated.id,
         v_updated.status,
         v_updated.cannot_attend_at,
         v_updated.scheduled_at,
         v_updated.study_id,
         v_updated.contributor_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_cannot_attend(uuid) TO authenticated;
