-- Fix 1: allow authenticated users to insert their own notifications.
-- The notifications table had SELECT/UPDATE/DELETE policies but no INSERT policy,
-- so any direct client-side insert was silently blocked by RLS.
-- Self-notifications (user_id = auth.uid()) are now allowed.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notifications' AND policyname = 'notifications_insert_own'
  ) THEN
    CREATE POLICY notifications_insert_own ON public.notifications
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;


-- Fix 2: replace insert_notification so the link column is actually written.
-- The original function body did not include `link` in its INSERT statement —
-- the column was added to the table after the function was written and the body
-- was never updated. The function accepted p_link but silently discarded it.
-- This replaces the body in-place (same 4-param signature, GRANT is preserved).
CREATE OR REPLACE FUNCTION public.insert_notification(
  p_user_id  uuid,
  p_title    text,
  p_body     text,
  p_link     text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, body, link, read, created_at)
  VALUES (p_user_id, p_title, p_body, p_link, false, now());
END;
$$;
