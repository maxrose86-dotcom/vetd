import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY       = Deno.env.get("RESEND_API_KEY");
const SUPABASE_URL         = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY    = Deno.env.get("PUBLIC_ANON_KEY")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function buildHtml(email: string): string {
  // ── REPLACE THIS BLOCK WITH YOUR TEMPLATE ──────────────────────────────────
  return `<!DOCTYPE html>
<html lang="sv">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Du är inne</title>
</head>
<body style="margin:0;padding:0;background:#f9fafb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f9fafb;padding:40px 16px">
    <tr><td align="center">
      <table width="100%" style="max-width:520px;background:#ffffff;border-radius:16px;border:1px solid #e5e7eb;padding:48px 40px">
        <tr><td>
          <p style="font-size:22px;font-weight:700;color:#111827;margin:0 0 4px">Vetd</p>
          <p style="font-size:28px;font-weight:700;color:#111827;margin:32px 0 16px;font-family:Georgia,serif">Du är inne.</p>
          <p style="font-size:15px;color:#374151;line-height:1.6;margin:0 0 24px">
            Din profil är nu live. Vi matchar dig med studier som passar din bakgrund och dina intressen.
          </p>
          <p style="font-size:15px;color:#374151;line-height:1.6;margin:0 0 32px">
            Du är tidig — de första studierna öppnar snart. Som tidig bidragsgivare får du prioriterad tillgång när vi öppnar upp.
          </p>
          <a href="https://vetd.se/app.html"
             style="display:inline-block;background:#00C47A;color:#ffffff;text-decoration:none;font-size:14px;font-weight:600;padding:12px 28px;border-radius:100px">
            Gå till din profil
          </a>
          <p style="font-size:12px;color:#9ca3af;margin:40px 0 0;line-height:1.6">
            Vetd · noreply@vetd.se<br>
            Du får det här mailet för att du registrerade dig som bidragsgivare.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  // ── END TEMPLATE ────────────────────────────────────────────────────────────
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Guard: API key must exist
  if (!RESEND_API_KEY) {
    console.error("[send-welcome-email] RESEND_API_KEY is missing");
    return new Response(JSON.stringify({ error: "RESEND_API_KEY missing" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ── Resolve authenticated user from Authorization header ────────────────────
  // Use a user-context client (anon key + forwarded Authorization header).
  // auth.getUser() with no args verifies the JWT against Supabase Auth.
  const authHeader = req.headers.get("Authorization")!;
  const token = authHeader.replace("Bearer ", "");

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: { Authorization: authHeader },
    },
  });

  const { data: { user }, error: authErr } = await userClient.auth.getUser(token);

  // Service role client used only for DB reads/writes below.
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  if (authErr || !user) {
    console.error("[send-welcome-email] Could not resolve user from token:", authErr?.message);
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  // ── End auth resolution ─────────────────────────────────────────────────────

  let email: string | undefined;

  try {
    const body = await req.json();
    email = body?.email;
  } catch (parseErr) {
    console.error("[send-welcome-email] Failed to parse request body:", parseErr);
    return new Response(JSON.stringify({ error: "invalid request body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!email || typeof email !== "string") {
    console.error("[send-welcome-email] email missing or invalid:", email);
    return new Response(JSON.stringify({ error: "email missing" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ── DB dedupe check ─────────────────────────────────────────────────────────
  const { data: contributor, error: fetchErr } = await adminClient
    .from("contributors")
    .select("welcome_email_sent_at")
    .eq("id", user.id)
    .maybeSingle();

  if (fetchErr) {
    console.error("[send-welcome-email] Failed to query contributors:", fetchErr);
    return new Response(JSON.stringify({ error: "db query failed" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (contributor?.welcome_email_sent_at) {
    console.log("[send-welcome-email] Already sent for userId:", user.id);
    return new Response(JSON.stringify({ ok: true, skipped: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  // ── End dedupe check ────────────────────────────────────────────────────────

  console.log("[send-welcome-email] Attempting send to:", email);

  let resendRes: Response;
  let resendBody: string;

  try {
    resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Vetd <noreply@vetd.se>",
        to:   [email],
        subject: "Du är inne",
        html: buildHtml(email),
      }),
    });

    resendBody = await resendRes.text();

    if (!resendRes.ok) {
      console.error("[send-welcome-email] Resend rejected request:", {
        status: resendRes.status,
        body: resendBody,
      });
      return new Response(JSON.stringify({ error: `Resend error ${resendRes.status}: ${resendBody}` }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  } catch (fetchErr) {
    console.error("[send-welcome-email] fetch to Resend failed:", fetchErr);
    return new Response(JSON.stringify({ error: String(fetchErr) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ── Mark as sent ────────────────────────────────────────────────────────────
  const { error: updateErr } = await adminClient
    .from("contributors")
    .update({ welcome_email_sent_at: new Date().toISOString() })
    .eq("id", user.id);

  if (updateErr) {
    console.error("[send-welcome-email] Failed to update welcome_email_sent_at:", updateErr);
    return new Response(JSON.stringify({ error: "failed to mark email as sent" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  // ── End mark as sent ────────────────────────────────────────────────────────

  let result: { id?: string };
  try {
    result = JSON.parse(resendBody);
  } catch {
    result = {};
  }

  console.log("[send-welcome-email] Sent successfully. Resend id:", result.id);
  return new Response(JSON.stringify({ ok: true, id: result.id }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
