-- applications.status: add 'cannot_attend' as a valid lifecycle state.
-- Set when a contributor confirms they can't attend a scheduled group session.
-- The column is unconstrained TEXT so no CHECK constraint alteration is required.
-- This migration adds a timestamp column so the client can show when the status changed,
-- and adds 'cant_attend' to the dedup trigger so repeat notifications are suppressed.

ALTER TABLE public.applications
  ADD COLUMN IF NOT EXISTS cannot_attend_at TIMESTAMPTZ DEFAULT NULL;

-- Extend the lifecycle notification dedup trigger to suppress duplicate cant_attend
-- notifications for the same application (DB-side safety net; JS checks status first).
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
  ELSIF NEW.notif_type IN ('application_accepted', 'application_rejected', 'added_to_session',
                            'availability_request', 'rating_received', 'cant_attend') THEN
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
