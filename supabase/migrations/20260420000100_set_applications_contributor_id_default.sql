ALTER TABLE public.applications
ALTER COLUMN contributor_id SET DEFAULT auth.uid();
