ALTER TABLE public.studies
  ADD COLUMN IF NOT EXISTS availability_requested_at timestamptz;

CREATE OR REPLACE FUNCTION public.notify_availability_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.availability_requested_at IS NOT NULL
     AND OLD.availability_requested_at IS NULL THEN
    INSERT INTO public.notifications (
      user_id,
      title,
      body,
      link,
      read,
      created_at,
      notif_type,
      params
    )
    SELECT DISTINCT
      a.contributor_id,
      'Availability requested',
      'Client requested your availability',
      NEW.id::text,
      false,
      now(),
      'availability_request',
      jsonb_build_object('study_id', NEW.id, 'application_id', a.id)
    FROM public.applications a
    LEFT JOIN public.contributors c ON c.id = a.contributor_id
    WHERE a.study_id = NEW.id
      AND a.status = 'accepted'
      AND a.contributor_id IS NOT NULL
      AND COALESCE(jsonb_array_length(to_jsonb(c.available_times)), 0) = 0;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS studies_availability_request_notify ON public.studies;

CREATE TRIGGER studies_availability_request_notify
AFTER UPDATE OF availability_requested_at ON public.studies
FOR EACH ROW
EXECUTE FUNCTION public.notify_availability_request();
