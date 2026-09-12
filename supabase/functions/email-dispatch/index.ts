import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "Esports Platform <onboarding@resend.dev>";
const SITE_URL = (Deno.env.get("SITE_URL") ?? "https://mysite-esports-platform.vercel.app").replace(/\/$/, "");

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });
}

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] ?? c));
}

function safeLink(href: string | null) {
  if (!href) return SITE_URL;
  try {
    const url = new URL(href, `${SITE_URL}/`);
    const base = new URL(SITE_URL);
    return url.origin === base.origin ? url.toString() : SITE_URL;
  } catch {
    return SITE_URL;
  }
}

function template(subject: string, body: string | null, href: string | null) {
  const link = safeLink(href);
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#050a08;color:#f0fdf4;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif"><div style="max-width:620px;margin:0 auto;padding:40px 20px"><div style="padding:30px;border:1px solid rgba(52,211,153,.2);border-radius:22px;background:#0a1a14"><div style="font-size:13px;letter-spacing:.1em;text-transform:uppercase;color:#2dd4bf;margin-bottom:14px">Esports Platform</div><h1 style="font-size:26px;line-height:1.25;margin:0 0 14px;color:#f0fdf4">${escapeHtml(subject)}</h1><p style="font-size:15px;line-height:1.65;color:#a7c7b8;margin:0 0 24px;white-space:pre-line">${escapeHtml(body ?? "У вас новое уведомление на Esports Platform.")}</p><a href="${escapeHtml(link)}" style="display:inline-block;padding:12px 18px;border-radius:12px;background:#34d399;color:#04100b;text-decoration:none;font-weight:700">Открыть уведомление</a><p style="font-size:12px;line-height:1.5;color:#6b9b87;margin:28px 0 0">Это автоматическое письмо. Настройки email-уведомлений можно изменить в профиле.</p></div></div></body></html>`;
}

async function isAuthorized(req: Request) {
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return false;
  try {
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    if (payload?.role === "service_role") return true;
  } catch {}
  const client = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data, error } = await client.rpc("is_tournament_admin");
  return !error && data === true;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!(await isAuthorized(req))) return json({ error: "Forbidden" }, 403);
  if (!RESEND_API_KEY) return json({ error: "RESEND_API_KEY is not configured", configured: false }, 503);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ error: "Supabase server credentials unavailable" }, 500);

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  let limit = 25;
  try {
    const payload = await req.json();
    if (Number.isFinite(payload?.limit)) limit = Math.max(1, Math.min(100, Number(payload.limit)));
  } catch {}

  const { data: jobs, error: claimError } = await service.rpc("email_claim_delivery_jobs", { p_limit: limit });
  if (claimError) return json({ error: claimError.message }, 500);

  const results: Array<Record<string, unknown>> = [];
  for (const job of jobs ?? []) {
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: EMAIL_FROM, to: [job.recipient_email], subject: job.subject, html: template(job.subject, job.body, job.href) }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result?.message ?? `Resend HTTP ${response.status}`);
      const { error: markError } = await service.rpc("email_mark_delivery_sent", { p_id: job.id, p_provider_message_id: result?.id ?? null });
      if (markError) throw markError;
      results.push({ id: job.id, status: "sent", provider_message_id: result?.id ?? null });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await service.rpc("email_mark_delivery_failed", { p_id: job.id, p_error: message });
      results.push({ id: job.id, status: "failed", error: message });
    }
  }

  return json({ configured: true, processed: results.length, results });
});
