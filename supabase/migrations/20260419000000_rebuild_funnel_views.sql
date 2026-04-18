-- ── REBUILD FUNNEL VIEWS ─────────────────────────────────────────────────────
-- This migration fixes the failure in 20260418090200_funnel_summary_v2.sql.
--
-- Root cause: CREATE OR REPLACE VIEW cannot drop columns (Postgres restriction).
-- 20260418090200 tried to remove `total_events` and rename `unique_visitors` →
-- `unique_people` in funnel_summary. That fails at runtime.
--
-- 20260418090300 then tried to create downstream views that depend on the
-- correctly-structured funnel_summary — and also failed because 090200 never
-- applied.
--
-- Fix: DROP all affected views in dependency order, then recreate them all.
-- The SQL here is the canonical version that both 090200 and 090300 intended
-- to produce. Those files remain in the repo as history but are superseded.
--
-- Safe to run multiple times (all DDL is CREATE OR REPLACE after the drops).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. DROP in reverse dependency order ──────────────────────────────────────
-- CASCADE catches any views that depend on these (e.g. if Supabase auto-created
-- any wrappers). IF EXISTS makes re-runs safe.

DROP VIEW IF EXISTS public.contributor_funnel_by_source CASCADE;
DROP VIEW IF EXISTS public.weekly_contributor_funnel    CASCADE;
DROP VIEW IF EXISTS public.daily_contributor_funnel     CASCADE;
DROP VIEW IF EXISTS public.funnel_by_utm                CASCADE;
DROP VIEW IF EXISTS public.funnel_summary               CASCADE;


-- ── 2. funnel_summary (stitched unique_people) ───────────────────────────────
-- Identity resolution priority:
--   1. user_id (authenticated)
--   2. anonymous_id stitched via id_map bridge
--   3. anonymous_id as-is (not yet matched)

CREATE OR REPLACE VIEW public.funnel_summary AS
WITH id_map AS (
  SELECT
    anonymous_id,
    MIN(user_id::text) AS canonical_user_id
  FROM public.funnel_events
  WHERE user_id    IS NOT NULL
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
)
SELECT
  step,
  event_name,
  COUNT(DISTINCT person_id) AS unique_people
FROM events
WHERE person_id IS NOT NULL
GROUP BY step, event_name
ORDER BY step;


-- ── 3. daily_contributor_funnel ───────────────────────────────────────────────
-- One row per calendar day. Same person counted once per day per event.

CREATE OR REPLACE VIEW public.daily_contributor_funnel AS
WITH id_map AS (
  SELECT
    anonymous_id,
    MIN(user_id::text) AS canonical_user_id
  FROM public.funnel_events
  WHERE user_id    IS NOT NULL
    AND anonymous_id IS NOT NULL
  GROUP BY anonymous_id
),
events AS (
  SELECT
    fe.occurred_at::date AS day,
    fe.event_name,
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
)
SELECT
  day,
  COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'homepage_view')                 AS homepage_view_people,
  COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'contributor_cta_click')         AS contributor_cta_click_people,
  COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'signup_started')                AS signup_started_people,
  COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'signup_completed')              AS signup_completed_people,
  COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'contributor_profile_completed') AS contributor_profile_completed_people,
  COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'first_study_accepted')          AS first_study_accepted_people
FROM events
GROUP BY day
ORDER BY day DESC;


-- ── 4. weekly_contributor_funnel ──────────────────────────────────────────────
-- One row per ISO week (Monday-anchored). Includes within-week conversion rates.
-- NOTE: rates are concurrent (this week's numerator / this week's denominator),
-- not strict cohort rates.

CREATE OR REPLACE VIEW public.weekly_contributor_funnel AS
WITH id_map AS (
  SELECT
    anonymous_id,
    MIN(user_id::text) AS canonical_user_id
  FROM public.funnel_events
  WHERE user_id    IS NOT NULL
    AND anonymous_id IS NOT NULL
  GROUP BY anonymous_id
),
events AS (
  SELECT
    date_trunc('week', fe.occurred_at)::date AS week,
    fe.event_name,
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
counts AS (
  SELECT
    week,
    COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'homepage_view')                 AS homepage_view_people,
    COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'contributor_cta_click')         AS contributor_cta_click_people,
    COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'signup_started')                AS signup_started_people,
    COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'signup_completed')              AS signup_completed_people,
    COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'contributor_profile_completed') AS contributor_profile_completed_people,
    COUNT(DISTINCT person_id) FILTER (WHERE event_name = 'first_study_accepted')          AS first_study_accepted_people
  FROM events
  GROUP BY week
)
SELECT
  week,
  homepage_view_people,
  contributor_cta_click_people,
  signup_started_people,
  signup_completed_people,
  contributor_profile_completed_people,
  first_study_accepted_people,
  -- Within-week conversion rates; NULLIF prevents divide-by-zero
  ROUND(contributor_cta_click_people::numeric         / NULLIF(homepage_view_people,                 0), 3) AS cta_rate,
  ROUND(signup_started_people::numeric                / NULLIF(contributor_cta_click_people,         0), 3) AS signup_start_rate,
  ROUND(signup_completed_people::numeric              / NULLIF(signup_started_people,                0), 3) AS signup_complete_rate,
  ROUND(contributor_profile_completed_people::numeric / NULLIF(signup_completed_people,              0), 3) AS activation_rate,
  ROUND(first_study_accepted_people::numeric          / NULLIF(contributor_profile_completed_people, 0), 3) AS first_accept_rate
FROM counts
ORDER BY week DESC;


-- ── 5. contributor_funnel_by_source ──────────────────────────────────────────
-- First-touch UTM attribution. Supersedes funnel_by_utm from 090200.
-- People with no UTM on any event → source '(direct)', medium/campaign '(none)'.

CREATE OR REPLACE VIEW public.contributor_funnel_by_source AS
WITH id_map AS (
  SELECT
    anonymous_id,
    MIN(user_id::text) AS canonical_user_id
  FROM public.funnel_events
  WHERE user_id    IS NOT NULL
    AND anonymous_id IS NOT NULL
  GROUP BY anonymous_id
),
events AS (
  SELECT
    fe.event_name,
    fe.utm_source,
    fe.utm_medium,
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
person_first_touch AS (
  SELECT DISTINCT ON (person_id)
    person_id,
    utm_source,
    utm_medium,
    utm_campaign
  FROM events
  WHERE utm_source IS NOT NULL
  ORDER BY person_id, occurred_at
)
SELECT
  COALESCE(ft.utm_source,   '(direct)') AS utm_source,
  COALESCE(ft.utm_medium,   '(none)')   AS utm_medium,
  COALESCE(ft.utm_campaign, '(none)')   AS utm_campaign,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'homepage_view')                 AS homepage_view_people,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'contributor_cta_click')         AS contributor_cta_click_people,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'signup_started')                AS signup_started_people,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'signup_completed')              AS signup_completed_people,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'contributor_profile_completed') AS contributor_profile_completed_people,
  COUNT(DISTINCT e.person_id) FILTER (WHERE e.event_name = 'first_study_accepted')          AS first_study_accepted_people
FROM events e
LEFT JOIN person_first_touch ft ON ft.person_id = e.person_id
GROUP BY 1, 2, 3
ORDER BY homepage_view_people DESC NULLS LAST;
