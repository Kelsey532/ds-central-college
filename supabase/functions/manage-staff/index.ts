import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = (Deno.env.get("ADMIN_ALLOWED_ORIGINS") || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

function corsHeaders(origin: string | null) {
  if (!origin || !allowedOrigins.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function respond(request: Request, body: Record<string, unknown>, status: number) {
  const headers = corsHeaders(request.headers.get("Origin"));
  if (!headers) return new Response(null, { status: 403 });
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  const headers = corsHeaders(request.headers.get("Origin"));
  if (!headers) return new Response(null, { status: 403 });
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return respond(request, { error: "Method not allowed." }, 405);

  const authorization = request.headers.get("Authorization");
  const bearer = authorization?.match(/^Bearer\s+(.+)$/i);
  if (!bearer) return respond(request, { error: "Authentication is required." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Required Supabase Edge Function environment variables are missing.");
    return respond(request, { error: "Staff account service is not configured." }, 500);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data: authData, error: authError } = await callerClient.auth.getUser(bearer[1]);
    if (authError || !authData.user) return respond(request, { error: "Your staff session is not valid." }, 401);

    const { data: callerProfile, error: callerError } = await serviceClient
      .from("profiles")
      .select("id,role,active")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (callerError) throw callerError;
    if (!callerProfile || !callerProfile.active || callerProfile.role !== "main_admin") {
      return respond(request, { error: "Only an active main admin can manage staff accounts." }, 403);
    }

    let input: unknown;
    try {
      input = await request.json();
    } catch {
      return respond(request, { error: "A valid JSON request body is required." }, 400);
    }
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      return respond(request, { error: "A valid account management request is required." }, 400);
    }

    const body = input as Record<string, unknown>;
    if (body.operation === "create") {
      const username = typeof body.username === "string" ? body.username.trim() : "";
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const password = typeof body.password === "string" ? body.password : "";
      const role = body.role;

      if (!username || username.length > 120) {
        return respond(request, { error: "Enter a username with no more than 120 characters." }, 400);
      }
      if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return respond(request, { error: "Enter a valid work email address." }, 400);
      }
      if (password.length < 12 || password.length > 128) {
        return respond(request, { error: "The initial password must be between 12 and 128 characters." }, 400);
      }
      if (role !== "editor" && role !== "main_admin") {
        return respond(request, { error: "Choose an editor or main admin account role." }, 400);
      }

      const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: username },
      });
      if (createError) return respond(request, { error: createError.message }, 400);
      if (!created.user) throw new Error("Supabase did not return the newly created user.");

      const { data: updatedProfile, error: updateError } = await serviceClient.rpc("activate_staff_profile", {
        p_actor_id: authData.user.id,
        p_target_id: created.user.id,
        p_username: username,
        p_role: role,
      });
      if (updateError || !updatedProfile) {
        const { error: deleteError } = await serviceClient.auth.admin.deleteUser(created.user.id);
        if (deleteError) console.error("Could not roll back an incomplete staff account.", deleteError);
        if (updateError) throw updateError;
        throw new Error("The new staff profile could not be activated.");
      }
      return respond(request, { id: created.user.id, email, full_name: username, role, active: true }, 201);
    }

    const targetId = typeof body.user_id === "string" ? body.user_id : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetId)) {
      return respond(request, { error: "Choose a valid staff account." }, 400);
    }
    if (targetId === authData.user.id) {
      return respond(request, { error: "You cannot change or delete your own main admin account." }, 403);
    }
    if (body.operation !== "update" && body.operation !== "delete") {
      return respond(request, { error: "Choose a supported account action." }, 400);
    }

    const { data: target, error: targetError } = await serviceClient
      .from("profiles")
      .select("id,role,active")
      .eq("id", targetId)
      .maybeSingle();
    if (targetError) throw targetError;
    if (!target) return respond(request, { error: "The selected staff account no longer exists." }, 404);

    if (body.operation === "update") {
      const role = body.role === undefined ? target.role : body.role;
      const active = body.active === undefined ? target.active : body.active;
      if ((role !== "editor" && role !== "main_admin") || typeof active !== "boolean") {
        return respond(request, { error: "Choose a valid role and active status." }, 400);
      }
      const { data, error } = await serviceClient.rpc("manage_staff_profile", {
        p_actor_id: authData.user.id,
        p_target_id: target.id,
        p_role: role,
        p_active: active,
      });
      if (error) {
        if (error.message.includes("last active super admin")) {
          return respond(request, { error: "The last active main admin cannot be demoted or deactivated." }, 409);
        }
        throw error;
      }
      return respond(request, { user: data }, 200);
    }

    const { error: disableError } = await serviceClient.rpc("manage_staff_profile", {
      p_actor_id: authData.user.id,
      p_target_id: target.id,
      p_role: target.role,
      p_active: false,
    });
    if (disableError) {
      if (disableError.message.includes("last active super admin")) {
        return respond(request, { error: "The last active main admin cannot be deleted." }, 409);
      }
      throw disableError;
    }

    const { error: deleteError } = await serviceClient.auth.admin.deleteUser(target.id);
    if (deleteError) {
      console.error("Staff account was deactivated, but authentication-user deletion failed.", deleteError);
      return respond(request, { error: "The account was disabled, but could not be fully deleted. Reload the list and retry." }, 502);
    }
    return respond(request, { id: target.id, deleted: true }, 200);
  } catch (error) {
    console.error("Staff account management failed.", error);
    return respond(request, { error: "Could not complete the staff account change." }, 500);
  }
});
