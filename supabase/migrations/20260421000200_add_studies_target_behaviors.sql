-- studies.target_behaviors: JSONB array of consumer behavior values
-- e.g. ["shops_online", "compares_brands"]
-- Null means no behavior targeting (default for all existing studies).
ALTER TABLE public.studies ADD COLUMN IF NOT EXISTS target_behaviors JSONB;
