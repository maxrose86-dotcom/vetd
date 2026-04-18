-- ── FUNNEL EVENTS ────────────────────────────────────────────────────────────
-- Flat, inspectable event log for the contributor acquisition funnel.
-- Write-only from the client (anon + authenticated).
-- Read via Supabase dashboard / SQL editor with service role.

CREATE TABLE IF NOT EXISTS public.funnel_events (
  id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  event_name   text        NOT NULL,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  anonymous_id text,
  user_id      uuid,                       -- nullable until auth exists
  session_id   text,
  page_path    text,
  locale       text,
  utm_source   text,
  utm_medium   text,
  utm_campaign text,
  referrer     text,
  device_type  text CHECK (device_type IN ('mobile', 'desktop', NULL))
);

CREATE INDEX IF NOT EXISTS funnel_events_name_idx       ON public.funnel_events (event_name);
CREATE INDEX IF NOT EXISTS funnel_events_occurred_idx   ON public.funnel_events (occurred_at);
CREATE INDEX IF NOT EXISTS funnel_events_user_id_idx    ON public.funnel_events (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS funnel_events_anon_id_idx    ON public.funnel_events (anonymous_id) WHERE anonymous_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS funnel_events_utm_source_idx ON public.funnel_events (utm_source) WHERE utm_source IS NOT NULL;

-- Write-only from the client; no client-side reads needed.
ALTER TABLE public.funnel_events ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'funnel_events' AND policyname = 'funnel_events_insert_anon') THEN
    CREATE POLICY funnel_events_insert_anon ON public.funnel_events
      FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'funnel_events' AND policyname = 'funnel_events_insert_auth') THEN
    CREATE POLICY funnel_events_insert_auth ON public.funnel_events
      FOR INSERT TO authenticated WITH CHECK (true);
  END IF;
END $$;


-- ── TRIGGER: first_study_accepted ────────────────────────────────────────────
-- Fires exactly once per contributor when their first application reaches
-- 'accepted' status — regardless of which side triggers the transition
-- (company accepting a pending app, or contributor accepting an invitation).

CREATE OR REPLACE FUNCTION public.fire_first_study_accepted()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- Only act on transitions INTO 'accepted'
  IF NEW.status = 'accepted' AND (OLD.status IS DISTINCT FROM 'accepted') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.funnel_events
       WHERE event_name = 'first_study_accepted'
         AND user_id    = NEW.contributor_id
    ) THEN
      INSERT INTO public.funnel_events (event_name, user_id)
      VALUES ('first_study_accepted', NEW.contributor_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_first_study_accepted ON public.applications;
CREATE TRIGGER trg_first_study_accepted
  AFTER UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.fire_first_study_accepted();


-- ── FUNNEL SUMMARY VIEW ───────────────────────────────────────────────────────
-- Inspect in Supabase SQL editor (service role).
-- Counts unique visitors per step using best-effort identity
-- (user_id when known, otherwise anonymous_id).

CREATE OR REPLACE VIEW public.funnel_summary AS
SELECT
  step,
  event_name,
  COUNT(DISTINCT COALESCE(user_id::text, anonymous_id)) AS unique_visitors,
  COUNT(*)                                               AS total_events
FROM (
  SELECT
    CASE event_name
      WHEN 'homepage_view'                 THEN 1
      WHEN 'contributor_cta_click'         THEN 2
      WHEN 'signup_started'                THEN 3
      WHEN 'signup_completed'              THEN 4
      WHEN 'contributor_profile_completed' THEN 5
      WHEN 'first_study_accepted'          THEN 6
    END AS step,
    event_name,
    user_id,
    anonymous_id
  FROM public.funnel_events
  WHERE event_name IN (
    'homepage_view', 'contributor_cta_click', 'signup_started',
    'signup_completed', 'contributor_profile_completed', 'first_study_accepted'
  )
) s
GROUP BY step, event_name
ORDER BY step;
