-- Add professional context fields for study matching
-- Safe nullable additions — no impact on existing rows or RLS
ALTER TABLE contributors ADD COLUMN IF NOT EXISTS job_title TEXT;
ALTER TABLE contributors ADD COLUMN IF NOT EXISTS industry TEXT;
ALTER TABLE contributors ADD COLUMN IF NOT EXISTS experience_level TEXT;
