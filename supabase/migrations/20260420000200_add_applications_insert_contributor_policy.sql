CREATE POLICY applications_insert_contributor
ON public.applications
FOR INSERT
TO authenticated
WITH CHECK (
  contributor_id = auth.uid()
);
