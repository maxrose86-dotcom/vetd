import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL             = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Reminder window: 23–25 hours before session start.
// A 2-hour window with an hourly cron interval guarantees every session
// gets exactly one day-before reminder tick, even with ±1–2 min scheduler jitter.
const WINDOW_LEAD_HR  = 23;
const WINDOW_TRAIL_HR = 25;

serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const now         = new Date();
    const windowStart = new Date(now.getTime() + WINDOW_LEAD_HR  * 60 * 60 * 1000).toISOString();
    const windowEnd   = new Date(now.getTime() + WINDOW_TRAIL_HR * 60 * 60 * 1000).toISOString();

    // ── Atomic claim ─────────────────────────────────────────────────────────
    // A single UPDATE ... WHERE day_before_reminder_sent_at IS NULL ... RETURNING is
    // translated by PostgREST into one SQL statement. Under PostgreSQL's default
    // READ COMMITTED isolation, two concurrent executions cannot both claim the
    // same row: the second UPDATE waits on the row lock, then re-evaluates the
    // WHERE clause and finds day_before_reminder_sent_at IS NULL is now false — it skips
    // the row. No separate SELECT step; no window between read and write.
    const { data: claimed, error: claimError } = await supabase
      .from("applications")
      .update({ day_before_reminder_sent_at: now.toISOString() })
      .eq("status", "accepted")
      .is("day_before_reminder_sent_at", null)
      .gte("scheduled_at", windowStart)
      .lte("scheduled_at", windowEnd)
      .not("contributor_id", "is", null)
      .select("id, contributor_id, study_id, room_url");

    if (claimError) throw claimError;
    if (!claimed || claimed.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { "Content-Type": "application/json" }, status: 200,
      });
    }

    // ── Fetch study metadata for notification copy ────────────────────────────
    // This fetch happens AFTER rows are claimed. A failure here must not abort
    // the batch — claimed rows that receive no notification are permanently lost
    // (day_before_reminder_sent_at is set and won't be retried). Log the error and proceed
    // with fallback values so every claimed row still gets a notification attempt.
    const studyIds = [...new Set(claimed.map((r: any) => r.study_id).filter(Boolean))];
    let studyMap = new Map<string, any>();
    if (studyIds.length > 0) {
      const { data: studies, error: studyError } = await supabase
        .from("studies")
        .select("id, title, session_type")
        .in("id", studyIds);
      if (studyError) {
        console.error("send-day-before-reminders: study metadata fetch failed, proceeding with fallbacks:", studyError.message);
      }
      studyMap = new Map((studies || []).map((s: any) => [s.id, s]));
    }

    // ── Send one notification per claimed row ─────────────────────────────────
    // Rows are already claimed. One failed notification must not stop the others.
    // If claim count != sent count, the discrepancy is visible in the response.
    let sent = 0;
    for (const row of claimed) {
      const study   = studyMap.get(row.study_id);
      const title   = study?.title   || "your study";
      const isGroup = study?.session_type === "group";

      const body = isGroup
        ? `Your group session for ${title} is tomorrow. You can join 15 minutes before start.`
        : `Your session for ${title} is tomorrow. You can join 15 minutes before start.`;

      const { error: notifError } = await supabase.rpc("insert_notification", {
        p_user_id:    row.contributor_id,
        p_title:      "Session tomorrow 📅",
        p_body:       body,
        p_link:       row.room_url || null,
        p_notif_type: null,
        p_params:     {},
      });

      if (notifError) {
        console.error(`send-day-before-reminders: notification failed for contributor ${row.contributor_id} (application ${row.id}):`, notifError.message);
      } else {
        sent++;
      }
    }

    return new Response(JSON.stringify({ sent, claimed: claimed.length }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });

  } catch (err: any) {
    console.error("send-day-before-reminders: fatal error:", err?.message ?? err);
    return new Response(JSON.stringify({ error: err?.message ?? "unknown error" }), {
      headers: { "Content-Type": "application/json" }, status: 500,
    });
  }
});
