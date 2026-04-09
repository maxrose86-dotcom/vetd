import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL             = Deno.env.get("SUPABASE_URL")!;
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
    const supabase      = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const sevenDaysAgo  = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

    const now = new Date().toISOString();

    const [
      { count: contributors_total },
      { count: contributors_7d },
      { count: applications_total },
      { count: applications_7d },
      { count: scheduled_total },
      { count: scheduled_7d },
      { count: completed_total },
      { count: completed_7d },
    ] = await Promise.all([
      supabase.from("contributors").select("*", { count: "exact", head: true }),
      supabase.from("contributors").select("*", { count: "exact", head: true }).gte("created_at", sevenDaysAgo),
      supabase.from("applications").select("*", { count: "exact", head: true }),
      supabase.from("applications").select("*", { count: "exact", head: true }).gte("applied_at", sevenDaysAgo),
      supabase.from("applications").select("*", { count: "exact", head: true }).not("scheduled_at", "is", null),
      supabase.from("applications").select("*", { count: "exact", head: true }).gte("scheduled_at", sevenDaysAgo).lte("scheduled_at", now),
      supabase.from("applications").select("*", { count: "exact", head: true }).eq("status", "completed"),
      supabase.from("applications").select("*", { count: "exact", head: true }).eq("status", "completed").gte("updated_at", sevenDaysAgo),
    ]);

    const apply_to_sched_rate = (applications_total ?? 0) > 0
      ? Math.round(((scheduled_total ?? 0) / applications_total!) * 100)
      : null;
    const sched_to_comp_rate = (scheduled_total ?? 0) > 0
      ? Math.round(((completed_total ?? 0) / scheduled_total!) * 100)
      : null;

    return new Response(JSON.stringify({
      contributors_total,
      contributors_7d,
      applications_total,
      applications_7d,
      scheduled_total,
      scheduled_7d,
      completed_total,
      completed_7d,
      apply_to_sched_rate,
      sched_to_comp_rate,
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });

  } catch (err: any) {
    console.error("get-metrics: fatal error:", err?.message ?? err);
    return new Response(
      JSON.stringify({ error: err?.message ?? "unknown error" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
