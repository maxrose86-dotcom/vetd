import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;

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

  try {
    const { email } = await req.json();
    if (!email || typeof email !== "string") {
      return new Response(JSON.stringify({ error: "email required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const res = await fetch("https://api.resend.com/emails", {
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

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Resend error ${res.status}: ${body}`);
    }

    const result = await res.json();
    return new Response(JSON.stringify({ ok: true, id: result.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
