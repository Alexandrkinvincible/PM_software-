// =====================================================================
// admin-create-user — the only privileged operation in Phase 1.
//
// Creating a login needs the service-role key, and that key bypasses
// every policy in 0002_rls.sql. It therefore never reaches the app.
// It lives here, where Supabase injects it, and this function does three
// things before it will use it:
//
//   1. Establishes who is calling, from their own JWT — not from
//      anything in the request body.
//   2. Confirms that person is an active Manager. SPEC section 3: admin
//      is Manager-only.
//   3. Confirms the projects being assigned actually exist.
//
// If any of those fails, the service-role key is never touched.
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const VALID_ROLES = [
  "manager",
  "pm",
  "assistant_pm",
  "super",
  "assistant_super",
  "foreman",
  "lead",
] as const;

type Role = (typeof VALID_ROLES)[number];

interface CreateUserRequest {
  email: string;
  name: string;
  phone?: string | null;
  role: Role;
  project_ids: string[];
  company_id?: string;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/// A password that can be read down a phone line on a job site without
/// being spelled twice. Ambiguous characters (0/O, 1/l/I) are excluded on
/// purpose. It is temporary by construction: must_change_password
/// defaults to true and the app has exactly one screen until it is false.
function temporaryPassword(): string {
  const alphabet = "abcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const pick = (set: string, n: number) =>
    Array.from(crypto.getRandomValues(new Uint32Array(n)))
      .map((v) => set[v % set.length])
      .join("");
  return `${pick(alphabet, 4)}-${pick(alphabet, 4)}-${pick(digits, 3)}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Not signed in." }, 401);
  }

  // ---- 1. Who is calling? Answered by their token, never the body. ----
  const caller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user: callerUser }, error: callerError } = await caller.auth
    .getUser();
  if (callerError || !callerUser) {
    return json({ error: "Not signed in." }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ---- 2. Are they an active Manager? ----
  // Checked with service-role rights so the answer does not itself depend
  // on the policies being correct. Two independent conditions: the
  // membership says manager, and the person is still active.
  const { data: managerRows, error: roleError } = await admin
    .from("project_members")
    .select("role, users!inner(is_active)")
    .eq("user_id", callerUser.id)
    .eq("role", "manager")
    .eq("active", true);

  if (roleError) return json({ error: roleError.message }, 500);

  const isActiveManager = (managerRows ?? []).some(
    // deno-lint-ignore no-explicit-any
    (row: any) => row.users?.is_active === true,
  );
  if (!isActiveManager) {
    return json({ error: "Only a Manager can add people." }, 403);
  }

  // ---- 3. Validate the request ----
  let body: CreateUserRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Malformed request." }, 400);
  }

  const email = (body.email ?? "").trim().toLowerCase();
  const name = (body.name ?? "").trim();

  if (!email.includes("@")) return json({ error: "A valid email is required." }, 400);
  if (name.length === 0) return json({ error: "A name is required." }, 400);
  if (!VALID_ROLES.includes(body.role)) {
    return json({ error: `Unknown role: ${body.role}` }, 400);
  }
  const projectIds = [...new Set(body.project_ids ?? [])];
  if (projectIds.length === 0) {
    return json({ error: "Assign the person to at least one job." }, 400);
  }

  const { data: foundProjects, error: projectError } = await admin
    .from("projects")
    .select("id")
    .in("id", projectIds);
  if (projectError) return json({ error: projectError.message }, 500);
  if ((foundProjects ?? []).length !== projectIds.length) {
    return json({ error: "One of those jobs does not exist." }, 400);
  }

  // Everyone belongs to a company; default to the house company unless
  // one is named. users.in_house is derived from it by a trigger, never
  // typed (0001_schema.sql).
  let companyId = body.company_id;
  if (!companyId) {
    const { data: house } = await admin
      .from("companies")
      .select("id")
      .eq("is_house", true)
      .single();
    if (!house) return json({ error: "No house company is configured." }, 500);
    companyId = house.id;
  }

  // ---- 4. Create the login ----
  const password = temporaryPassword();
  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true, // no self-service anywhere, including confirmation
    });

  if (createError || !created?.user) {
    const alreadyExists = (createError?.message ?? "").toLowerCase().includes(
      "already",
    );
    return json(
      {
        error: alreadyExists
          ? "Someone already has that email."
          : createError?.message ?? "Could not create the login.",
      },
      alreadyExists ? 409 : 500,
    );
  }

  const newUserId = created.user.id;

  // ---- 5. Profile and memberships ----
  // If either insert fails the auth user is removed again, so a failed
  // run leaves nothing behind for the Manager to clean up by hand.
  const { error: profileError } = await admin.from("users").insert({
    id: newUserId,
    email,
    name,
    phone: body.phone ?? null,
    default_role: body.role,
    company_id: companyId,
    must_change_password: true,
  });

  if (profileError) {
    await admin.auth.admin.deleteUser(newUserId);
    return json({ error: profileError.message }, 500);
  }

  const { error: membershipError } = await admin.from("project_members").insert(
    projectIds.map((project_id) => ({
      user_id: newUserId,
      project_id,
      role: body.role,
    })),
  );

  if (membershipError) {
    // users has a delete-blocking trigger (SPEC principle 9), so the
    // profile row cannot be removed. Deactivate it instead and take the
    // auth user away, which is what "never created" means here.
    await admin.from("users").update({ is_active: false }).eq("id", newUserId);
    await admin.auth.admin.deleteUser(newUserId);
    return json({ error: membershipError.message }, 500);
  }

  // The password is returned once and is not stored anywhere readable.
  return json({
    user_id: newUserId,
    email,
    temporary_password: password,
  }, 201);
});
