CREATE OR REPLACE FUNCTION public.mark_completed(
  p_application_id uuid
)
RETURNS TABLE(
  id uuid,
  status text,
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
  v_study record;
BEGIN
  SELECT a.*
    INTO v_app
    FROM public.applications a
   WHERE a.id = p_application_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application is not a completed session';
  END IF;

  SELECT s.*
    INTO v_study
    FROM public.studies s
   WHERE s.id = v_app.study_id;

  IF NOT FOUND OR v_study.created_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Application is not a completed session';
  END IF;

  IF v_app.status <> 'accepted' OR v_app.scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Application is not a completed session';
  END IF;

  UPDATE public.applications a
     SET status = 'completed',
         updated_at = now()
   WHERE a.id = p_application_id
     AND a.status = 'accepted'
     AND a.scheduled_at IS NOT NULL;

  INSERT INTO public.payouts (
    application_id,
    contributor_id,
    study_id,
    amount,
    status,
    created_at
  )
  SELECT
    a.id,
    a.contributor_id,
    a.study_id,
    s.pay_per_participant,
    'pending_review',
    now()
  FROM public.applications a
  JOIN public.studies s ON s.id = a.study_id
  WHERE a.id = p_application_id
    AND NOT EXISTS (
      SELECT 1 FROM public.payouts p
      WHERE p.application_id = a.id
    );

  RETURN QUERY
  SELECT a.id,
         a.status::text AS status,
         a.scheduled_at,
         a.study_id,
         a.contributor_id
    FROM public.applications a
   WHERE a.id = p_application_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_completed(uuid) TO authenticated;
