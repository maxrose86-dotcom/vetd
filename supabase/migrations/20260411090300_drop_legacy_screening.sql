-- Backfill: migrate any non-null screening_q1/screening_q2 values into screening_questions JSONB.
-- Only affects studies that have old-style questions but no new JSONB questions yet.
-- Legacy columns (screening_q1, screening_q2) are intentionally left in place.
-- They will be dropped in a follow-up cleanup migration once the new screener flow is verified live.
UPDATE studies
SET screening_questions = (
  SELECT jsonb_agg(q ORDER BY ord)
  FROM (
    SELECT jsonb_build_object('text', sq, 'type', 'text') AS q, ord
    FROM unnest(ARRAY[screening_q1, screening_q2]) WITH ORDINALITY AS t(sq, ord)
    WHERE sq IS NOT NULL AND sq <> ''
  ) sub
)
WHERE screening_questions IS NULL
  AND (
    (screening_q1 IS NOT NULL AND screening_q1 <> '') OR
    (screening_q2 IS NOT NULL AND screening_q2 <> '')
  );
