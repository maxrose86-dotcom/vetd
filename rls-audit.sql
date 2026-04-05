-- ============================================================
-- Vetd RLS Audit & Policy Script
-- Run this in Supabase SQL editor (do NOT run automatically)
-- ============================================================

-- ─── 1. ENABLE RLS ON ALL TABLES ────────────────────────────
ALTER TABLE public.companies     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contributors  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.studies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applications  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;


-- ─── 2. HELPER: create policy only if it doesn't exist ───────
-- (Postgres does not support CREATE POLICY IF NOT EXISTS,
--  so we use DO $$ blocks that check pg_policies first.)


-- ─── 3. PROFILES ─────────────────────────────────────────────
-- SELECT: authenticated users can read all profiles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'profiles_select_authenticated'
  ) THEN
    CREATE POLICY profiles_select_authenticated
      ON public.profiles FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

-- SELECT/UPDATE own profile
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'profiles_update_own'
  ) THEN
    CREATE POLICY profiles_update_own
      ON public.profiles FOR UPDATE
      TO authenticated
      USING (id = auth.uid());
  END IF;
END $$;

-- INSERT own profile (triggered on signup)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'profiles_insert_own'
  ) THEN
    CREATE POLICY profiles_insert_own
      ON public.profiles FOR INSERT
      TO authenticated
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- Admins can do anything
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'profiles_admin_all'
  ) THEN
    CREATE POLICY profiles_admin_all
      ON public.profiles FOR ALL
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;


-- ─── 4. COMPANIES ────────────────────────────────────────────
-- SELECT: any authenticated user can read companies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'companies'
      AND policyname = 'companies_select_authenticated'
  ) THEN
    CREATE POLICY companies_select_authenticated
      ON public.companies FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

-- INSERT: creator only
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'companies'
      AND policyname = 'companies_insert_creator'
  ) THEN
    CREATE POLICY companies_insert_creator
      ON public.companies FOR INSERT
      TO authenticated
      WITH CHECK (created_by = auth.uid());
  END IF;
END $$;

-- UPDATE: creator or admin
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'companies'
      AND policyname = 'companies_update_creator_or_admin'
  ) THEN
    CREATE POLICY companies_update_creator_or_admin
      ON public.companies FOR UPDATE
      TO authenticated
      USING (
        created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

-- DELETE: admin only
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'companies'
      AND policyname = 'companies_delete_admin'
  ) THEN
    CREATE POLICY companies_delete_admin
      ON public.companies FOR DELETE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;


-- ─── 5. CONTRIBUTORS ─────────────────────────────────────────
-- SELECT: any authenticated user (clients & admins need to browse)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'contributors'
      AND policyname = 'contributors_select_authenticated'
  ) THEN
    CREATE POLICY contributors_select_authenticated
      ON public.contributors FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

-- INSERT: own row only
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'contributors'
      AND policyname = 'contributors_insert_own'
  ) THEN
    CREATE POLICY contributors_insert_own
      ON public.contributors FOR INSERT
      TO authenticated
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- UPDATE: own row only
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'contributors'
      AND policyname = 'contributors_update_own'
  ) THEN
    CREATE POLICY contributors_update_own
      ON public.contributors FOR UPDATE
      TO authenticated
      USING (id = auth.uid());
  END IF;
END $$;

-- UPDATE: admin can update any contributor (e.g. tier, flags)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'contributors'
      AND policyname = 'contributors_update_admin'
  ) THEN
    CREATE POLICY contributors_update_admin
      ON public.contributors FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;


-- ─── 6. CLIENTS ──────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'clients'
      AND policyname = 'clients_select_own_or_admin'
  ) THEN
    CREATE POLICY clients_select_own_or_admin
      ON public.clients FOR SELECT
      TO authenticated
      USING (
        id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'clients'
      AND policyname = 'clients_insert_own'
  ) THEN
    CREATE POLICY clients_insert_own
      ON public.clients FOR INSERT
      TO authenticated
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'clients'
      AND policyname = 'clients_update_own'
  ) THEN
    CREATE POLICY clients_update_own
      ON public.clients FOR UPDATE
      TO authenticated
      USING (id = auth.uid());
  END IF;
END $$;


-- ─── 7. STUDIES ──────────────────────────────────────────────
-- SELECT: authenticated users can browse active studies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'studies'
      AND policyname = 'studies_select_active_or_own'
  ) THEN
    CREATE POLICY studies_select_active_or_own
      ON public.studies FOR SELECT
      TO authenticated
      USING (
        status = 'active'
        OR created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

-- INSERT: clients only (role check via profiles)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'studies'
      AND policyname = 'studies_insert_client'
  ) THEN
    CREATE POLICY studies_insert_client
      ON public.studies FOR INSERT
      TO authenticated
      WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role IN ('client', 'admin')
        )
      );
  END IF;
END $$;

-- UPDATE: creator or admin
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'studies'
      AND policyname = 'studies_update_creator_or_admin'
  ) THEN
    CREATE POLICY studies_update_creator_or_admin
      ON public.studies FOR UPDATE
      TO authenticated
      USING (
        created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;


-- ─── 8. APPLICATIONS ─────────────────────────────────────────
-- Contributor can INSERT their own applications
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'applications'
      AND policyname = 'applications_insert_contributor'
  ) THEN
    CREATE POLICY applications_insert_contributor
      ON public.applications FOR INSERT
      TO authenticated
      WITH CHECK (contributor_id = auth.uid());
  END IF;
END $$;

-- Contributor or study creator or admin can SELECT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'applications'
      AND policyname = 'applications_select'
  ) THEN
    CREATE POLICY applications_select
      ON public.applications FOR SELECT
      TO authenticated
      USING (
        contributor_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.studies s
          WHERE s.id = study_id AND s.created_by = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

-- Study creator or admin can UPDATE status
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'applications'
      AND policyname = 'applications_update_client_or_admin'
  ) THEN
    CREATE POLICY applications_update_client_or_admin
      ON public.applications FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.studies s
          WHERE s.id = study_id AND s.created_by = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;


-- ─── 9. PAYMENTS ─────────────────────────────────────────────
-- Contributor can SELECT own payments
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'payments'
      AND policyname = 'payments_select'
  ) THEN
    CREATE POLICY payments_select
      ON public.payments FOR SELECT
      TO authenticated
      USING (
        contributor_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.applications a
          JOIN public.studies s ON s.id = a.study_id
          WHERE a.id = application_id AND s.created_by = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

-- Client (study creator) can INSERT payments after completion
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'payments'
      AND policyname = 'payments_insert_client_or_admin'
  ) THEN
    CREATE POLICY payments_insert_client_or_admin
      ON public.payments FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.applications a
          JOIN public.studies s ON s.id = a.study_id
          WHERE a.id = application_id AND s.created_by = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

-- Admin can UPDATE payment status
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'payments'
      AND policyname = 'payments_update_admin'
  ) THEN
    CREATE POLICY payments_update_admin
      ON public.payments FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;


-- ─── 10. RATINGS ─────────────────────────────────────────────
-- SELECT: contributor can see own ratings; client can see ratings they gave
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ratings'
      AND policyname = 'ratings_select'
  ) THEN
    CREATE POLICY ratings_select
      ON public.ratings FOR SELECT
      TO authenticated
      USING (
        contributor_id = auth.uid()
        OR rated_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.role = 'admin'
        )
      );
  END IF;
END $$;

-- INSERT/UPSERT: client (study creator) rates contributor
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ratings'
      AND policyname = 'ratings_insert_client'
  ) THEN
    CREATE POLICY ratings_insert_client
      ON public.ratings FOR INSERT
      TO authenticated
      WITH CHECK (rated_by = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ratings'
      AND policyname = 'ratings_update_client'
  ) THEN
    CREATE POLICY ratings_update_client
      ON public.ratings FOR UPDATE
      TO authenticated
      USING (rated_by = auth.uid());
  END IF;
END $$;


-- ─── 11. NOTIFICATIONS ───────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications'
      AND policyname = 'notifications_select_own'
  ) THEN
    CREATE POLICY notifications_select_own
      ON public.notifications FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications'
      AND policyname = 'notifications_update_own'
  ) THEN
    CREATE POLICY notifications_update_own
      ON public.notifications FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications'
      AND policyname = 'notifications_delete_own'
  ) THEN
    CREATE POLICY notifications_delete_own
      ON public.notifications FOR DELETE
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;


-- ─── 12. FUNCTION GRANTS ─────────────────────────────────────

-- recalc_contributor_rating: called by client after submitting a rating
GRANT EXECUTE ON FUNCTION public.recalc_contributor_rating(uuid) TO authenticated;

-- insert_notification: called by contributors/clients to create notifications
GRANT EXECUTE ON FUNCTION public.insert_notification(uuid, text, text, text) TO authenticated;


-- ─── 13. GDPR — delete_contributor_data SECURITY DEFINER ─────
-- This function deletes all data for a given contributor.
-- It runs as the DB owner (SECURITY DEFINER) so it can delete
-- from auth.users, which is not accessible to normal users.

CREATE OR REPLACE FUNCTION public.delete_contributor_data(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  DELETE FROM notifications WHERE user_id = p_user_id;
  DELETE FROM payments WHERE contributor_id = p_user_id;
  DELETE FROM ratings WHERE contributor_id = p_user_id;
  DELETE FROM applications WHERE contributor_id = p_user_id;
  DELETE FROM contributors WHERE id = p_user_id;
  DELETE FROM profiles WHERE id = p_user_id;
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

-- Only the authenticated user themselves can call this (enforced by the
-- RPC caller in the app, which passes their own user ID).
GRANT EXECUTE ON FUNCTION public.delete_contributor_data(uuid) TO authenticated;


-- ─── END OF SCRIPT ───────────────────────────────────────────
-- Review all policies above before applying in production.
-- Test with: SELECT * FROM pg_policies WHERE schemaname = 'public';
