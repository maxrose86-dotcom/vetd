-- ── OPERATOR FUNNEL VIEWS ────────────────────────────────────────────────────
-- Three read-only views for weekly acquisition review inside Supabase.
-- All three share the same id_map + person_id stitching logic from
-- 20260418_funnel_summary_v2.sql. No schema changes, no new tables.
--
-- Views created here:
--   daily_contributor_funnel     — unique people per day per funnel step
--   weekly_contributor_funnel    — unique people per week + step conversion rates
--   contributor_funnel_by_source — same counts, attributed by first-touch UTM
--
-- Also supersedes funnel_by_utm from v2 (contributor_funnel_by_source
-- adds utm_medium and is the canonical source breakdown going forward).


-- ── A. DAILY FUNNEL ──────────────────────────────────────────────────────────
-- One row per calendar day.
-- A person who fires the same event multiple times on the same day is counted once.

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


-- ── B. WEEKLY FUNNEL ─────────────────────────────────────────────────────────
-- One row per ISO calendar week (Monday-anchored, date_trunc default).
-- Conversion rates are within-week: e.g. cta_rate = (people who clicked CTA
-- this week) / (people who viewed homepage this week). This is a concurrent
-- rate, not a strict cohort rate — see assumptions.

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
  ROUND(contributor_cta_click_people::numeric         / NULLIF(homepage_view_people,                     0), 3) AS cta_rate,
  ROUND(signup_started_people::numeric                / NULLIF(contributor_cta_click_people,             0), 3) AS signup_start_rate,
  ROUND(signup_completed_people::numeric              / NULLIF(signup_started_people,                    0), 3) AS signup_complete_rate,
  ROUND(contributor_profile_completed_people::numeric / NULLIF(signup_completed_people,                  0), 3) AS activation_rate,
  ROUND(first_study_accepted_people::numeric          / NULLIF(contributor_profile_completed_people,     0), 3) AS first_accept_rate
FROM counts
ORDER BY week DESC;


-- ── C. FUNNEL BY SOURCE ──────────────────────────────────────────────────────
-- First-touch attribution: each person is assigned the utm_source / utm_medium /
-- utm_campaign from their earliest event that has a non-null utm_source.
-- People with no UTM on any event → source '(direct)', medium/campaign '(none)'.
-- Supersedes funnel_by_utm from 20260418_funnel_summary_v2.sql.

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
  -- Earliest UTM tuple per person; DISTINCT ON + ORDER BY occurred_at is deterministic
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
