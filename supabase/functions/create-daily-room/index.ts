import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const DAILY_API_KEY = Deno.env.get("DAILY_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("Missing authorization header");
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) throw new Error("Unauthorized");

    const body = await req.json();
    const { scheduled_at, study_id, application_id, is_reschedule } = body;
    if (!scheduled_at) throw new Error("Missing scheduled_at");

    const scheduledDate = new Date(scheduled_at);
    const expiryDate = new Date(scheduledDate.getTime() + 3 * 60 * 60 * 1000);

    // Dispatch based on which identifier the caller provides — DB record determines the mode,
    // not any client-supplied session_type hint.
    if (study_id) {
      // ── Group mode ────────────────────────────────────────────────────────
      // Caller handles bulk DB update and per-contributor notifications.
      // This function only creates the shared room and returns its details.

      // Authoritative source: read session_type and spots from DB, never from client input
      const { data: study, error: studyErr } = await supabase
        .from("studies")
        .select("id, title, created_by, session_type, spots")
        .eq("id", study_id)
        .single();
      if (studyErr || !study) throw new Error("Study not found");
      if (study.created_by !== user.id) throw new Error("Not your study");
      if (study.session_type !== "group") throw new Error("Study is not a group session");

      // max_participants derived from DB state, not client input: participants + 1 moderator slot, minimum 2
      const maxParticipants = Math.max(2, (study.spots || 1) + 1);
      const roomName = `vetd-group-${study_id.slice(0, 8)}-${Date.now()}`;
      const dailyRes = await fetch("https://api.daily.co/v1/rooms", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${DAILY_API_KEY}` },
        body: JSON.stringify({ name: roomName, properties: {
          exp: Math.floor(expiryDate.getTime() / 1000),
          enable_chat: true, enable_screenshare: true,
          max_participants: maxParticipants,
          enable_recording: false, start_audio_off: true, start_video_off: false
        }})
      });
      if (!dailyRes.ok) { const errBody = await dailyRes.text(); throw new Error(`Daily API error: ${errBody}`); }
      const room = await dailyRes.json();

      return new Response(
        JSON.stringify({ success: true, room_url: room.url, room_name: room.name }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );

    } else if (application_id) {
      // ── One-to-one mode (existing flow) ──────────────────────────────────

      const { data: app, error: appError } = await supabase
        .from("applications")
        .select("id, study_id, contributor_id, studies(created_by, title)")
        .eq("id", application_id)
        .single();
      if (appError || !app) throw new Error("Application not found");
      if (app.studies?.created_by !== user.id) throw new Error("Not your study");

      const roomName = `vetd-${application_id.slice(0, 8)}-${Date.now()}`;
      const dailyRes = await fetch("https://api.daily.co/v1/rooms", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${DAILY_API_KEY}` },
        body: JSON.stringify({ name: roomName, properties: {
          exp: Math.floor(expiryDate.getTime() / 1000),
          enable_chat: true, enable_screenshare: true,
          max_participants: 2,
          enable_recording: false, start_audio_off: true, start_video_off: false
        }})
      });
      if (!dailyRes.ok) { const errBody = await dailyRes.text(); throw new Error(`Daily API error: ${errBody}`); }
      const room = await dailyRes.json();

      const { error: updateError } = await supabase
        .from("applications")
        .update({ scheduled_at, room_name: room.name, room_url: room.url, reminder_sent_at: null })
        .eq("id", application_id);
      if (updateError) throw updateError;

      const studyTitle = app.studies?.title || "a study";
      const dateStr = scheduledDate.toLocaleDateString("sv-SE", { day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" });
      const notifTitle = is_reschedule ? "Session rescheduled!" : "Session scheduled!";
      const notifBody  = is_reschedule
        ? `Your session for "${studyTitle}" has been rescheduled to ${dateStr}. You can join 15 minutes before start.`
        : `Your session for "${studyTitle}" is confirmed for ${dateStr}. You can join 15 minutes before start.`;
      await supabase.rpc("insert_notification", {
        p_user_id:    app.contributor_id,
        p_title:      notifTitle,
        p_body:       notifBody,
        p_link:       null,
        p_notif_type: null,
        p_params:     {},
      });

      return new Response(
        JSON.stringify({ success: true, room_url: room.url, room_name: room.name }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    } else {
      throw new Error("Missing study_id (group) or application_id (one-to-one)");
    }
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    );
  }
});
