-- ================================================================
-- Vetd — RLS policies + GDPR function
-- Safe to re-run: all CREATE POLICY statements are wrapped in
-- DO $$ IF NOT EXISTS blocks. Already-existing policies are skipped.
-- ================================================================


-- ── 0. ADMIN HELPER ─────────────────────────────────────────────
-- SECURITY DEFINER bypasses RLS when reading profiles, which
-- prevents infinite recursion inside the profiles table policies.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS
$$ SELECT EXISTS (
     SELECT 1 FROM public.profiles
     WHERE id = auth.uid() AND role = 'admin'
   ) $$;


-- ── 1. ENABLE RLS ───────────────────────────────────────────────
ALTER TABLE public.profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contributors  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.studies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applications  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;


-- ── 2. PROFILES ─────────────────────────────────────────────────
-- Any authenticated user can read profiles (needed for name lookups)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profiles_select_authenticated') THEN
    CREATE POLICY profiles_select_authenticated ON public.profiles
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Users can only update their own profile
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profiles_update_own') THEN
    CREATE POLICY profiles_update_own ON public.profiles
      FOR UPDATE TO authenticated USING (id = auth.uid());
  END IF;
END $$;

-- Users can insert their own profile row (created on sign-up)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profiles_insert_own') THEN
    CREATE POLICY profiles_insert_own ON public.profiles
      FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- NOTE: No profiles_admin_all policy — it causes infinite recursion
-- because it would query profiles from within a profiles policy.
-- Admins manage profiles via the Supabase dashboard (service role key).


-- ── 3. COMPANIES ────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_select_authenticated') THEN
    CREATE POLICY companies_select_authenticated ON public.companies
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_insert_creator') THEN
    CREATE POLICY companies_insert_creator ON public.companies
      FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_update_creator_or_admin') THEN
    CREATE POLICY companies_update_creator_or_admin ON public.companies
      FOR UPDATE TO authenticated
      USING (created_by = auth.uid() OR public.is_admin());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_delete_admin') THEN
    CREATE POLICY companies_delete_admin ON public.companies
      FOR DELETE TO authenticated USING (public.is_admin());
  END IF;
END $$;


-- ── 4. CONTRIBUTORS ─────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='contributors' AND policyname='contributors_select_authenticated') THEN
    CREATE POLICY contributors_select_authenticated ON public.contributors
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='contributors' AND policyname='contributors_insert_own') THEN
    CREATE POLICY contributors_insert_own ON public.contributors
      FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='contributors' AND policyname='contributors_update_own_or_admin') THEN
    CREATE POLICY contributors_update_own_or_admin ON public.contributors
      FOR UPDATE TO authenticated
      USING (id = auth.uid() OR public.is_admin());
  END IF;
END $$;


-- ── 5. CLIENTS ──────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='clients' AND policyname='clients_select_own_or_admin') THEN
    CREATE POLICY clients_select_own_or_admin ON public.clients
      FOR SELECT TO authenticated
      USING (id = auth.uid() OR public.is_admin());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='clients' AND policyname='clients_insert_own') THEN
    CREATE POLICY clients_insert_own ON public.clients
      FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='clients' AND policyname='clients_update_own') THEN
    CREATE POLICY clients_update_own ON public.clients
      FOR UPDATE TO authenticated USING (id = auth.uid());
  END IF;
END $$;


-- ── 6. STUDIES ──────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='studies' AND policyname='studies_select') THEN
    CREATE POLICY studies_select ON public.studies
      FOR SELECT TO authenticated
      USING (status = 'active' OR created_by = auth.uid() OR public.is_admin());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='studies' AND policyname='studies_insert_creator') THEN
    CREATE POLICY studies_insert_creator ON public.studies
      FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='studies' AND policyname='studies_update_creator_or_admin') THEN
    CREATE POLICY studies_update_creator_or_admin ON public.studies
      FOR UPDATE TO authenticated
      USING (created_by = auth.uid() OR public.is_admin());
  END IF;
END $$;


-- ── 7. APPLICATIONS ─────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='applications' AND policyname='applications_select') THEN
    CREATE POLICY applications_select ON public.applications
      FOR SELECT TO authenticated
      USING (
        contributor_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.studies s WHERE s.id = study_id AND s.created_by = auth.uid())
        OR public.is_admin()
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='applications' AND policyname='applications_insert_contributor') THEN
    CREATE POLICY applications_insert_contributor ON public.applications
      FOR INSERT TO authenticated WITH CHECK (contributor_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='applications' AND policyname='applications_update_client_or_admin') THEN
    CREATE POLICY applications_update_client_or_admin ON public.applications
      FOR UPDATE TO authenticated
      USING (
        EXISTS (SELECT 1 FROM public.studies s WHERE s.id = study_id AND s.created_by = auth.uid())
        OR public.is_admin()
      );
  END IF;
END $$;


-- ── 8. PAYMENTS ─────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='payments' AND policyname='payments_select') THEN
    CREATE POLICY payments_select ON public.payments
      FOR SELECT TO authenticated
      USING (
        contributor_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.applications a
          JOIN public.studies s ON s.id = a.study_id
          WHERE a.id = application_id AND s.created_by = auth.uid()
        )
        OR public.is_admin()
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='payments' AND policyname='payments_insert_client_or_admin') THEN
    CREATE POLICY payments_insert_client_or_admin ON public.payments
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.applications a
          JOIN public.studies s ON s.id = a.study_id
          WHERE a.id = application_id AND s.created_by = auth.uid()
        )
        OR public.is_admin()
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='payments' AND policyname='payments_update_admin') THEN
    CREATE POLICY payments_update_admin ON public.payments
      FOR UPDATE TO authenticated USING (public.is_admin());
  END IF;
END $$;


-- ── 9. RATINGS ──────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ratings' AND policyname='ratings_select') THEN
    CREATE POLICY ratings_select ON public.ratings
      FOR SELECT TO authenticated
      USING (contributor_id = auth.uid() OR rated_by = auth.uid() OR public.is_admin());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ratings' AND policyname='ratings_insert_client') THEN
    CREATE POLICY ratings_insert_client ON public.ratings
      FOR INSERT TO authenticated WITH CHECK (rated_by = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ratings' AND policyname='ratings_update_client') THEN
    CREATE POLICY ratings_update_client ON public.ratings
      FOR UPDATE TO authenticated USING (rated_by = auth.uid());
  END IF;
END $$;


-- ── 10. NOTIFICATIONS ───────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='notifications_select_own') THEN
    CREATE POLICY notifications_select_own ON public.notifications
      FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='notifications_update_own') THEN
    CREATE POLICY notifications_update_own ON public.notifications
      FOR UPDATE TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='notifications_delete_own') THEN
    CREATE POLICY notifications_delete_own ON public.notifications
      FOR DELETE TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;


-- ── 11. FUNCTION GRANTS ─────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.is_admin()                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalc_contributor_rating(uuid)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_notification(uuid,text,text,text) TO authenticated;


-- ── 12. GDPR — delete_contributor_data ──────────────────────────
CREATE OR REPLACE FUNCTION public.delete_contributor_data(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.notifications  WHERE user_id        = p_user_id;
  DELETE FROM public.payments       WHERE contributor_id = p_user_id;
  DELETE FROM public.ratings        WHERE contributor_id = p_user_id;
  DELETE FROM public.applications   WHERE contributor_id = p_user_id;
  DELETE FROM public.contributors   WHERE id             = p_user_id;
  DELETE FROM public.profiles       WHERE id             = p_user_id;
  DELETE FROM auth.users            WHERE id             = p_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.delete_contributor_data(uuid) TO authenticated;


-- ── VERIFY ──────────────────────────────────────────────────────
-- Run this after to confirm everything applied:
-- SELECT tablename, policyname, cmd
-- FROM pg_policies WHERE schemaname = 'public'
-- ORDER BY tablename, cmd;
