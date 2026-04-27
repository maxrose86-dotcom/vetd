CREATE OR REPLACE FUNCTION public.skip_duplicate_lifecycle_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_study_id text := COALESCE(NEW.params->>'study_id', NEW.link);
  v_application_id text := NEW.params->>'application_id';
  v_scheduled_at text := NEW.params->>'scheduled_at';
BEGIN
  IF NEW.notif_type IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.notif_type = 'study_invited' THEN
    IF EXISTS (
      SELECT 1 FROM public.notifications n
       WHERE n.user_id = NEW.user_id
         AND n.notif_type = NEW.notif_type
         AND COALESCE(n.params->>'study_id', n.link) = v_study_id
    ) THEN
      RETURN NULL;
    END IF;
  ELSIF NEW.notif_type IN ('application_accepted', 'application_rejected', 'added_to_session', 'availability_request', 'rating_received') THEN
    IF EXISTS (
      SELECT 1 FROM public.notifications n
       WHERE n.user_id = NEW.user_id
         AND n.notif_type = NEW.notif_type
         AND n.params->>'application_id' = v_application_id
    ) THEN
      RETURN NULL;
    END IF;
  ELSIF NEW.notif_type IN ('session_scheduled', 'session_rescheduled') THEN
    IF EXISTS (
      SELECT 1 FROM public.notifications n
       WHERE n.user_id = NEW.user_id
         AND n.notif_type = NEW.notif_type
         AND n.params->>'application_id' = v_application_id
         AND COALESCE(n.params->>'scheduled_at', '') = COALESCE(v_scheduled_at, '')
    ) THEN
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notifications_lifecycle_dedupe ON public.notifications;
CREATE TRIGGER notifications_lifecycle_dedupe
BEFORE INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.skip_duplicate_lifecycle_notification();

CREATE OR REPLACE FUNCTION public.insert_notification(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_link text DEFAULT NULL,
  p_notif_type text DEFAULT NULL,
  p_params jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
  VALUES (p_user_id, p_title, p_body, p_link, false, now(), p_notif_type, p_params);
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_notification(uuid, text, text, text, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_application_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title text;
BEGIN
  IF NEW.contributor_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT title INTO v_title
    FROM public.studies
   WHERE id = NEW.study_id;

  IF TG_OP = 'INSERT' AND NEW.status = 'invited' THEN
    INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
    VALUES (
      NEW.contributor_id,
      'You''ve been invited to a study',
      'You''ve been personally selected to participate in "' || COALESCE(v_title, 'this study') || '". Open Vetd to accept.',
      NEW.study_id::text,
      false,
      now(),
      'study_invited',
      jsonb_build_object('study_id', NEW.study_id, 'application_id', NEW.id, 'contributor_id', NEW.contributor_id)
    );
  ELSIF TG_OP = 'UPDATE'
        AND OLD.status IS DISTINCT FROM NEW.status
        AND OLD.status IN ('pending', 'invited')
        AND NEW.status = 'accepted'
        AND NEW.scheduled_at IS NULL THEN
    INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
    VALUES (
      NEW.contributor_id,
      'Session confirmed',
      'Your session for "' || COALESCE(v_title, 'this study') || '" has been confirmed. You''ll receive scheduling details shortly.',
      NULL,
      false,
      now(),
      'application_accepted',
      jsonb_build_object('study_id', NEW.study_id, 'application_id', NEW.id, 'contributor_id', NEW.contributor_id)
    );
  ELSIF TG_OP = 'UPDATE'
        AND OLD.status IS DISTINCT FROM NEW.status
        AND OLD.status = 'pending'
        AND NEW.status = 'rejected' THEN
    INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
    VALUES (
      NEW.contributor_id,
      'Study update',
      'We''re unable to move forward with your participation in "' || COALESCE(v_title, 'this study') || '" at this time. Thank you for your interest.',
      NULL,
      false,
      now(),
      'application_rejected',
      jsonb_build_object('study_id', NEW.study_id, 'application_id', NEW.id, 'contributor_id', NEW.contributor_id)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS applications_lifecycle_notify ON public.applications;
CREATE TRIGGER applications_lifecycle_notify
AFTER INSERT OR UPDATE OF status ON public.applications
FOR EACH ROW
EXECUTE FUNCTION public.notify_application_lifecycle();

CREATE OR REPLACE FUNCTION public.notify_rating_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_study_id uuid;
  v_study_title text;
  v_overall text;
BEGIN
  IF NEW.contributor_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT a.study_id, s.title
    INTO v_study_id, v_study_title
    FROM public.applications a
    LEFT JOIN public.studies s ON s.id = a.study_id
   WHERE a.id = NEW.application_id;

  v_overall := round(((COALESCE(NEW.punctuality, 0) + COALESCE(NEW.engagement, 0) + COALESCE(NEW.quality, 0) + COALESCE(NEW.honesty, 0) + COALESCE(NEW.profile_fit, 0)) / 5.0)::numeric, 2)::text;

  INSERT INTO public.notifications (user_id, title, body, link, read, created_at, notif_type, params)
  VALUES (
    NEW.contributor_id,
    'You received a new rating for "' || COALESCE(v_study_title, 'this study') || '"',
    'Your overall score for this study was ' || v_overall || ' stars. Keep up the great work!',
    NULL,
    false,
    now(),
    'rating_received',
    jsonb_build_object('study_id', v_study_id, 'application_id', NEW.application_id, 'contributor_id', NEW.contributor_id)
  );

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.ratings') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS ratings_received_notify ON public.ratings;
    CREATE TRIGGER ratings_received_notify
    AFTER INSERT ON public.ratings
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_rating_received();
  END IF;
END $$;
