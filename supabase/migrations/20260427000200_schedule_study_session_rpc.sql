CREATE OR REPLACE FUNCTION public.schedule_study_session(
  p_study_id uuid,
  p_application_id uuid,
  p_scheduled_at timestamptz,
  p_room_url text,
  p_room_name text,
  p_session_type text,
  p_is_reschedule boolean,
  p_notification_title text,
  p_notification_body text
)
RETURNS TABLE(session_id text, final_status text, scheduled_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_study record;
  v_app record;
  v_old_status text;
  v_count integer := 0;
  v_notif_type text := CASE WHEN p_is_reschedule THEN 'session_rescheduled' ELSE 'session_scheduled' END;
BEGIN
  IF p_scheduled_at IS NULL OR p_scheduled_at <= now() THEN
    RAISE EXCEPTION 'schedule_time_must_be_future';
  END IF;

  IF COALESCE(p_room_url, '') = '' OR COALESCE(p_room_name, '') = '' THEN
    RAISE EXCEPTION 'schedule_room_required';
  END IF;

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

  IF v_study.status NOT IN ('active', 'paused', 'draft') THEN
    RAISE EXCEPTION 'study_not_schedulable';
  END IF;

  IF COALESCE(v_study.is_test, false) IS NOT TRUE
     AND COALESCE(v_study.payment_status, 'unpaid') <> 'paid' THEN
    RAISE EXCEPTION 'study_payment_required';
  END IF;

  IF p_session_type = 'group' THEN
    IF v_study.session_type <> 'group' THEN
      RAISE EXCEPTION 'study_not_group_session';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM public.applications
       WHERE study_id = p_study_id
         AND status = 'accepted'
         AND scheduled_at = p_scheduled_at
    ) THEN
      RAISE EXCEPTION 'session_already_exists_for_time';
    END IF;

    PERFORM 1
      FROM public.applications
     WHERE study_id = p_study_id
       AND status = 'accepted'
     FOR UPDATE;

    SELECT count(*)
      INTO v_count
      FROM public.applications
     WHERE study_id = p_study_id
       AND status = 'accepted';

    IF v_count = 0 THEN
      RAISE EXCEPTION 'no_accepted_participants';
    END IF;

    UPDATE public.applications
       SET scheduled_at = p_scheduled_at,
           room_url = p_room_url,
           room_name = p_room_name,
           updated_at = now(),
           reminder_sent_at = NULL,
           day_before_reminder_sent_at = NULL,
           joined_call_at = NULL
     WHERE study_id = p_study_id
       AND status = 'accepted';

    UPDATE public.notifications n
       SET read = true
      FROM public.applications a
     WHERE a.study_id = p_study_id
       AND a.status = 'accepted'
       AND a.contributor_id IS NOT NULL
       AND n.user_id = a.contributor_id
       AND n.notif_type IN ('session_scheduled', 'session_rescheduled')
       AND n.read = false
       AND n.params->>'application_id' = a.id::text;

    INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
    SELECT DISTINCT
           a.contributor_id,
           p_notification_title,
           p_notification_body,
           NULL,
           false,
           now(),
           v_notif_type,
           jsonb_build_object(
             'study_id', p_study_id,
             'application_id', a.id,
             'scheduled_at', p_scheduled_at,
             'session_type', 'group'
           )
      FROM public.applications a
     WHERE a.study_id = p_study_id
       AND a.status = 'accepted'
       AND a.contributor_id IS NOT NULL;

    RETURN QUERY SELECT p_room_name, v_study.status::text, v_count;
    RETURN;
  END IF;

  IF p_application_id IS NULL THEN
    RAISE EXCEPTION 'application_required';
  END IF;

  IF v_study.session_type = 'group' THEN
    RAISE EXCEPTION 'use_group_scheduler';
  END IF;

  SELECT *
    INTO v_app
    FROM public.applications
   WHERE id = p_application_id
     AND study_id = p_study_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'application_not_found';
  END IF;

  IF v_app.status NOT IN ('pending', 'invited', 'accepted') THEN
    RAISE EXCEPTION 'application_not_schedulable';
  END IF;

  IF v_app.status = 'accepted'
     AND v_app.scheduled_at IS NOT NULL
     AND p_is_reschedule IS NOT TRUE THEN
    RAISE EXCEPTION 'application_already_scheduled';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.applications
     WHERE study_id = p_study_id
       AND id <> p_application_id
       AND status = 'accepted'
       AND scheduled_at = p_scheduled_at
  ) THEN
    RAISE EXCEPTION 'session_already_exists_for_time';
  END IF;

  v_old_status := v_app.status;

  UPDATE public.applications
     SET status = 'accepted',
         scheduled_at = p_scheduled_at,
         room_url = p_room_url,
         room_name = p_room_name,
         updated_at = now(),
         reminder_sent_at = NULL,
         day_before_reminder_sent_at = NULL,
         joined_call_at = NULL
   WHERE id = p_application_id;

  IF v_old_status IN ('pending', 'invited') THEN
    UPDATE public.studies
       SET filled_spots = LEAST(COALESCE(filled_spots, 0) + 1, COALESCE(spots, COALESCE(filled_spots, 0) + 1))
     WHERE id = p_study_id;
  END IF;

  UPDATE public.notifications
     SET read = true
   WHERE user_id = v_app.contributor_id
     AND notif_type IN ('session_scheduled', 'session_rescheduled')
     AND read = false
     AND params->>'application_id' = p_application_id::text;

  IF v_app.contributor_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
    VALUES (
      v_app.contributor_id,
      p_notification_title,
      p_notification_body,
      NULL,
      false,
      now(),
      v_notif_type,
      jsonb_build_object(
        'study_id', p_study_id,
        'application_id', p_application_id,
        'scheduled_at', p_scheduled_at,
        'session_type', 'one_to_one'
      )
    );
  END IF;

  RETURN QUERY SELECT p_room_name, v_study.status::text, 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.schedule_study_session(
  uuid,
  uuid,
  timestamptz,
  text,
  text,
  text,
  boolean,
  text,
  text
) TO authenticated;
