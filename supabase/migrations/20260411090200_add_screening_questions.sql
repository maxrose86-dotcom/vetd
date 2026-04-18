-- Study-specific screening questions and per-application answers
-- studies.screening_questions: JSONB array of {text, type, options?}
-- applications.screening_answers: JSONB array of strings, index-aligned with questions
ALTER TABLE studies      ADD COLUMN IF NOT EXISTS screening_questions JSONB;
ALTER TABLE applications ADD COLUMN IF NOT EXISTS screening_answers   JSONB;
