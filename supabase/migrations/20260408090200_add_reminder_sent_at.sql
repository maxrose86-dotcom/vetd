-- Migration: add reminder_sent_at to applications
-- Tracks whether a 30-minute pre-session reminder has been sent for this scheduled row.
-- NULL = not yet sent. Set to now() by the send-reminders Edge Function when claimed.
-- Must be reset to NULL whenever scheduled_at changes (reschedule), so the contributor
-- receives a fresh reminder at the new time.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS is idempotent.

ALTER TABLE public.applications
  ADD COLUMN IF NOT EXISTS reminder_sent_at TIMESTAMPTZ DEFAULT NULL;
