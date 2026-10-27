// Öğretmen / admin davet eder.
// Yetki ve kota kontrolleri invitations tablosunun RLS kuralları ve
// tetikleyicisi tarafından çağıranın kendi oturumuyla yapılır; servis
// anahtarı sadece Supabase Auth davet e-postasını göndermek için kullanılır.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Oturum gerekli", code: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Geçersiz istek", code: "bad_request" }, 400);
  }

  const tenantId = String(body.tenant_id ?? "");
  const email = String(body.email ?? "").trim().toLowerCase();
  const fullName = String(body.full_name ?? "").trim();
  const phone = body.phone ? String(body.phone).trim() : null;
  const role = body.role === "admin" ? "admin" : "teacher";
  const redirectTo = typeof body.redirect_to === "string" ? body.redirect_to : Deno.env.get("APP_URL");

  if (!tenantId || !email.includes("@") || !fullName) {
    return json({ error: "Ad soyad ve geçerli bir e-posta gerekli", code: "bad_request" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const adminClient = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const { data: invitation, error: insertError } = await userClient
    .from("invitations")
    .insert({ tenant_id: tenantId, email, full_name: fullName, phone, role })
    .select()
    .single();

  if (insertError) {
    return json({ error: insertError.message, code: insertError.hint || insertError.code }, 400);
  }

  const { error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
    redirectTo,
    data: { full_name: fullName },
  });

  if (inviteError) {
    await adminClient.from("invitations").delete().eq("id", invitation.id);
    return json({ error: inviteError.message, code: "invite_failed" }, 400);
  }

  return json({ ok: true, invitation_id: invitation.id });
});
