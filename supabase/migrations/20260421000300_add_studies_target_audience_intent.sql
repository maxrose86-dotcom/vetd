-- studies.target_audience_intent: single value indicating recruitment frame
-- Values: 'general' | 'category_buyers' | 'existing_customers'
-- Null means not set (treat as 'general'). Safe default for all existing studies.
ALTER TABLE public.studies ADD COLUMN IF NOT EXISTS target_audience_intent TEXT;
