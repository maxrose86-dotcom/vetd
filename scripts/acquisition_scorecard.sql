-- ── VETD ACQUISITION SCORECARD ───────────────────────────────────────────────
-- Run these queries in the Supabase SQL editor (service role) every Monday.
-- No schema changes. No views required. Pure read-only.
--
-- Queries in this file:
--   1. Weekly scorecard  — last 8 full weeks, per-metric labels, weekly verdict
--   2. Channel scorecard — all-time by first-touch UTM, channel verdict
--
-- ─────────────────────────────────────────────────────────────────────────────
-- DECISION METRICS
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Chosen metrics (in priority order for scaling decisions):
--
--   activation_rate       — profile_completed / signup_completed
--                           PRIMARY gate. Measures whether the funnel pays off.
--                           If bad, more traffic just wastes spend.
--
--   signup_complete_rate  — signup_completed / signup_started
--                           CRITICAL leak. Email-confirm + form completion.
--                           Bad here = fixable without touching homepage or spend.
--
--   cta_rate              — cta_clicks / homepage_views
--                           HOMEPAGE quality. Bad here = homepage or audience problem.
--
--   first_accept_rate     — first_accepted / profile_completed
--                           LAGGING indicator. Reflects study supply + matching.
--                           Informational only — not a primary spend gate.
--
-- Dropped from verdict (too noisy at this stage):
--   signup_start_rate     — depends on app.html bounce, not homepage or spend quality.
--                           Include as an output column but not a hold/scale trigger.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THRESHOLDS
-- ─────────────────────────────────────────────────────────────────────────────
--
--   Metric                    bad          acceptable      strong
--   ─────────────────────────────────────────────────────────────
--   cta_rate                  < 0.04       0.04 – 0.10     > 0.10
--   signup_complete_rate      < 0.35       0.35 – 0.60     > 0.60
--   activation_rate           < 0.20       0.20 – 0.45     > 0.45
--   first_accept_rate         < 0.10       0.10 – 0.35     > 0.35
--
--   Minimum weekly volume:    homepage_view_people < 50  →  hold (unreliable rates)
--   Source minimum volume:    homepage_view_people < 30  →  test_more (not enough signal)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- VERDICT LOGIC
-- ─────────────────────────────────────────────────────────────────────────────
--
--   hold:
--     volume < 50
--     OR  cta_rate          is bad   (homepage is not working — top of funnel broken)
--     OR  signup_complete_rate is bad (email/form dropout is too high — fix first)
--     OR  activation_rate   is bad   (onboarding is broken — money will not convert)
--
--   ready_to_scale:
--     volume >= 50
--     AND  cta_rate          not bad     (homepage earns its keep)
--     AND  signup_complete_rate not bad  (email/form flow is passable)
--     AND  activation_rate   is strong   (economics work at scale)
--     AND  first_accept_rate not bad     (contributors get value)
--
--   watch:
--     anything else — funnel is alive but one or more metrics need improvement
--
-- ─────────────────────────────────────────────────────────────────────────────


-- ══ 1. WEEKLY ACQUISITION SCORECARD ══════════════════════════════════════════
-- Last 8 full calendar weeks.
-- Run first every Monday. Read the verdict column before anything else.

WITH weeks AS (
  SELECT *
  FROM public.weekly_contributor_funnel
  WHERE week < date_trunc('week', now())::date
  ORDER BY week DESC
  LIMIT 8
),
labeled AS (
  SELECT
    week,
    homepage_view_people,
    contributor_cta_click_people,
    signup_started_people,
    signup_completed_people,
    contributor_profile_completed_people  AS activated_people,
    first_study_accepted_people,

    cta_rate,
    signup_start_rate,
    signup_complete_rate,
    activation_rate,
    first_accept_rate,

    -- Volume gate
    CASE WHEN homepage_view_people < 50 THEN true ELSE false END AS low_volume,

    -- cta_rate status
    CASE
      WHEN cta_rate IS NULL OR cta_rate < 0.04   THEN 'bad'
      WHEN cta_rate <= 0.10                       THEN 'acceptable'
      ELSE                                             'strong'
    END AS cta_rate_status,

    -- signup_complete_rate status
    CASE
      WHEN signup_complete_rate IS NULL OR signup_complete_rate < 0.35   THEN 'bad'
      WHEN signup_complete_rate <= 0.60                                   THEN 'acceptable'
      ELSE                                                                     'strong'
    END AS signup_complete_rate_status,

    -- activation_rate status
    CASE
      WHEN activation_rate IS NULL OR activation_rate < 0.20   THEN 'bad'
      WHEN activation_rate <= 0.45                              THEN 'acceptable'
      ELSE                                                           'strong'
    END AS activation_rate_status,

    -- first_accept_rate status (informational — not a hold trigger)
    CASE
      WHEN first_accept_rate IS NULL OR first_accept_rate < 0.10   THEN 'bad'
      WHEN first_accept_rate <= 0.35                                THEN 'acceptable'
      ELSE                                                               'strong'
    END AS first_accept_rate_status

  FROM weeks
)
SELECT
  week,
  homepage_view_people,
  -- Funnel volume
  contributor_cta_click_people,
  signup_completed_people,
  activated_people,
  first_study_accepted_people,
  -- Rates + status labels
  cta_rate,             cta_rate_status,
  signup_complete_rate, signup_complete_rate_status,
  activation_rate,      activation_rate_status,
  first_accept_rate,    first_accept_rate_status,
  -- signup_start_rate is informational only (not in verdict)
  signup_start_rate,
  -- Overall verdict
  CASE
    -- Hard stops: insufficient data or broken funnel mechanic
    WHEN low_volume                          THEN 'hold'
    WHEN cta_rate_status          = 'bad'    THEN 'hold'
    WHEN signup_complete_rate_status = 'bad' THEN 'hold'
    WHEN activation_rate_status   = 'bad'    THEN 'hold'
    -- Ready to scale: volume ok, no bad metrics, activation is strong
    WHEN NOT low_volume
     AND cta_rate_status          != 'bad'
     AND signup_complete_rate_status != 'bad'
     AND activation_rate_status   = 'strong'
     AND first_accept_rate_status != 'bad'    THEN 'ready_to_scale'
    -- Everything else: alive but not ready
    ELSE 'watch'
  END AS verdict

FROM labeled
ORDER BY week DESC;


-- ══ 2. CHANNEL ACQUISITION SCORECARD ═════════════════════════════════════════
-- All-time, attributed by first-touch UTM (source / medium / campaign).
-- Run after the weekly scorecard when verdict is ready_to_scale or watch.
-- Use it to decide WHERE to increase, hold, or pause spend.
--
-- Key metric: e2e_activation_rate = profile_completed / homepage_views
--   This is the single most important channel efficiency number.
--   It answers: of every 100 visitors from this source, how many became
--   active contributors?
--
-- Source verdict:
--   scale_candidate:  >= 30 views  AND  e2e_activation_rate >= 0.03
--   pause:            >= 30 views  AND  e2e_activation_rate < 0.01
--   test_more:        < 30 views   OR   0.01 <= e2e_activation_rate < 0.03

SELECT
  utm_source,
  utm_medium,
  utm_campaign,
  -- Volume
  homepage_view_people,
  contributor_cta_click_people,
  signup_completed_people,
  contributor_profile_completed_people  AS activated_people,
  first_study_accepted_people,
  -- End-to-end channel efficiency (homepage as denominator)
  ROUND(contributor_cta_click_people::numeric         / NULLIF(homepage_view_people, 0), 3) AS cta_rate,
  ROUND(signup_completed_people::numeric              / NULLIF(homepage_view_people, 0), 3) AS e2e_signup_rate,
  ROUND(contributor_profile_completed_people::numeric / NULLIF(homepage_view_people, 0), 3) AS e2e_activation_rate,
  ROUND(first_study_accepted_people::numeric          / NULLIF(homepage_view_people, 0), 3) AS e2e_first_accept_rate,
  -- Channel verdict
  CASE
    WHEN homepage_view_people < 30
      THEN 'test_more'
    WHEN (contributor_profile_completed_people::numeric / NULLIF(homepage_view_people, 0)) >= 0.03
      THEN 'scale_candidate'
    WHEN (contributor_profile_completed_people::numeric / NULLIF(homepage_view_people, 0)) < 0.01
      THEN 'pause'
    ELSE 'test_more'
  END AS verdict

FROM public.contributor_funnel_by_source
ORDER BY homepage_view_people DESC NULLS LAST;
