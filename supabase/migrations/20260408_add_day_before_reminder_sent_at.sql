-- Migration: add day_before_reminder_sent_at to applications
-- Dedup gate for the 24-hour-before reminder dispatcher.
-- Cleared on every schedule/reschedule, same pattern as reminder_sent_at.

ALTER TABLE public.applications
  ADD COLUMN IF NOT EXISTS day_before_reminder_sent_at TIMESTAMPTZ DEFAULT NULL;
