DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'applications'
      AND policyname = 'applications_insert_contributor'
  ) THEN
    CREATE POLICY applications_insert_contributor
    ON public.applications
    FOR INSERT
    TO authenticated
    WITH CHECK (
      contributor_id = auth.uid()
    );
  END IF;
END $$;
