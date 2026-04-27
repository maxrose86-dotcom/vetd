CREATE OR REPLACE FUNCTION public.add_participant_to_session(
  p_study_id uuid,
  p_contributor_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_study record;
  v_session record;
  v_app record;
BEGIN
  SELECT *
    INTO v_study
    FROM public.studies
   WHERE id = p_study_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'study_not_found';
  END IF;

  IF v_study.created_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not_study_owner';
  END IF;

  IF v_study.session_type <> 'group' THEN
    RAISE EXCEPTION 'study_not_group_session';
  END IF;

  SELECT scheduled_at, room_url, room_name
    INTO v_session
    FROM public.applications
   WHERE study_id = p_study_id
     AND status = 'accepted'
     AND scheduled_at IS NOT NULL
   ORDER BY scheduled_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_scheduled_session';
  END IF;

  SELECT *
    INTO v_app
    FROM public.applications
   WHERE study_id = p_study_id
     AND contributor_id = p_contributor_id
     AND status = 'accepted'
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'accepted_application_not_found';
  END IF;

  IF v_app.scheduled_at IS NOT NULL THEN
    RETURN;
  END IF;

  UPDATE public.applications
     SET scheduled_at = v_session.scheduled_at,
         room_url = v_session.room_url,
         room_name = v_session.room_name,
         updated_at = now(),
         reminder_sent_at = NULL,
         day_before_reminder_sent_at = NULL,
         joined_call_at = NULL,
         last_call_activity = NULL
   WHERE id = v_app.id;

  INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
  VALUES (
    p_contributor_id,
    'Added to scheduled session',
    'You were added to a scheduled session',
    NULL,
    false,
    now(),
    'added_to_session',
    jsonb_build_object(
      'study_id', p_study_id,
      'application_id', v_app.id,
      'scheduled_at', v_session.scheduled_at,
      'session_type', 'group'
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_participant_to_session(uuid, uuid) TO authenticated;
