-- ── FUNNEL SUMMARY V2 ────────────────────────────────────────────────────────
-- Replaces the view from 20260418_funnel_events.sql.
--
-- person_id resolution (in priority order):
--   1. user_id (authenticated identity — always wins when present)
--   2. anonymous_id looked up via id_map (pre-auth events stitched to a known user)
--   3. anonymous_id directly (not yet matched to any user)
--
-- Stitching: any event row where BOTH user_id and anonymous_id are non-null
-- forms a bridge. id_map uses MIN(user_id) per anonymous_id to stay deterministic
-- in the edge case where one device/browser was used by multiple accounts.


-- ── 1. FUNNEL SUMMARY VIEW ───────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.funnel_summary AS
WITH id_map AS (
  -- Bridge: anonymous_id → canonical user_id
  -- Only rows that have both fields set (post-signup events in app.html)
  SELECT
    anonymous_id,
    MIN(user_id::text) AS canonical_user_id
  FROM public.funnel_events
  WHERE user_id IS NOT NULL
    AND anonymous_id IS NOT NULL
  GROUP BY anonymous_id
),
events AS (
  SELECT
    CASE fe.event_name
      WHEN 'homepage_view'                 THEN 1
      WHEN 'contributor_cta_click'         THEN 2
      WHEN 'signup_started'                THEN 3
      WHEN 'signup_completed'              THEN 4
      WHEN 'contributor_profile_completed' THEN 5
      WHEN 'first_study_accepted'          THEN 6
    END AS step,
    fe.event_name,
    COALESCE(
      fe.user_id::text,       -- post-auth: use user_id directly
      im.canonical_user_id,   -- pre-auth: stitch via anonymous_id → user_id bridge
      fe.anonymous_id         -- no match yet: use anonymous_id as-is
    ) AS person_id
  FROM public.funnel_events fe
  LEFT JOIN id_map im ON im.anonymous_id = fe.anonymous_id
  WHERE fe.event_name IN (
    'homepage_view', 'contributor_cta_click', 'signup_started',
    'signup_completed', 'contributor_profile_completed', 'first_study_accepted'
  )
)
SELECT
  step,
  event_name,
  COUNT(DISTINCT person_id) AS unique_people
FROM events
WHERE person_id IS NOT NULL
GROUP BY step, event_name
ORDER BY step;


-- ── 2. UTM BREAKDOWN VIEW ────────────────────────────────────────────────────
-- Uses first-touch attribution: each person is attributed to the UTM source
-- from their earliest event that carries a non-null utm_source.
-- This prevents a single person from being counted under both '(direct)' and
-- a campaign source when they had multiple sessions.

CREATE OR REPLACE VIEW public.funnel_by_utm AS
WITH id_map AS (
  SELECT
    anonymous_id,
    MIN(user_id::text) AS canonical_user_id
  FROM public.funnel_events
  WHERE user_id IS NOT NULL
    AND anonymous_id IS NOT NULL
  GROUP BY anonymous_id
),
events AS (
  SELECT
    fe.event_name,
    fe.utm_source,
    fe.utm_campaign,
    fe.occurred_at,
    COALESCE(
      fe.user_id::text,
      im.canonical_user_id,
      fe.anonymous_id
    ) AS person_id
  FROM public.funnel_events fe
  LEFT JOIN id_map im ON im.anonymous_id = fe.anonymous_id
  WHERE fe.event_name IN (
    'homepage_view', 'contributor_cta_click', 'signup_started',
    'signup_completed', 'contributor_profile_completed', 'first_study_accepted'
  )
    AND COALESCE(fe.user_id::text, im.canonical_user_id, fe.anonymous_id) IS NOT NULL
),
person_utm AS (
  -- First-touch: earliest event per person that has a utm_source
  SELECT DISTINCT ON (person_id)
    person_id,
    utm_source,
    utm_campaign
  FROM events
  WHERE utm_source IS NOT NULL
  ORDER BY person_id, occurred_at
)
SELECT
  COALESCE(pu.utm_source,   '(direct)') AS utm_source,
  COALESCE(pu.utm_campaign, '(none)')   AS utm_campaign,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'homepage_view')                 AS hp_views,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'contributor_cta_click')         AS cta_clicks,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'signup_started')                AS started,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'signup_completed')              AS completed,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'contributor_profile_completed') AS activated,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'first_study_accepted')          AS first_accepted
FROM events e
LEFT JOIN person_utm pu ON pu.person_id = e.person_id
GROUP BY 1, 2
ORDER BY hp_views DESC NULLS LAST;
