ALTER TABLE public.studies
ADD COLUMN IF NOT EXISTS audience_type TEXT;

ALTER TABLE public.studies
ALTER COLUMN audience_type SET DEFAULT 'customers';

UPDATE public.studies
SET audience_type = 'customers'
WHERE audience_type IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'studies_audience_type_check'
  ) THEN
    ALTER TABLE public.studies
    ADD CONSTRAINT studies_audience_type_check
    CHECK (audience_type IN ('customers', 'professionals'));
  END IF;
END $$;
