-- Enforce one participation row per contributor per study.
-- Participation is stored in public.applications with study_id + contributor_id.

DELETE FROM public.applications a
USING (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY study_id, contributor_id
      ORDER BY updated_at DESC NULLS LAST, applied_at DESC NULLS LAST, id DESC
    ) AS rn
  FROM public.applications
  WHERE study_id IS NOT NULL
    AND contributor_id IS NOT NULL
) ranked
WHERE a.id = ranked.id
  AND ranked.rn > 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'unique_study_contributor'
      AND conrelid = 'public.applications'::regclass
  ) THEN
    ALTER TABLE public.applications
      ADD CONSTRAINT unique_study_contributor
      UNIQUE (study_id, contributor_id);
  END IF;
END $$;
