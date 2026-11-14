/*
 * Shared Supabase client and typed-by-contract helpers for the static site.
 * The anon key is public; database RLS is the security boundary. Never put a
 * service-role key or account password in this file.
 */
(function () {
  "use strict";

  const config = window.DSCC_CONFIG || {};
  const supabaseUrl = String(config.supabaseUrl || "").trim();
  const supabaseAnonKey = String(config.supabaseAnonKey || "").trim();

  window.DSCC_CONFIG = Object.assign({}, config, {
    supabaseUrl,
    supabaseAnonKey
  });

  const client = supabaseUrl && supabaseAnonKey && window.supabase
    ? window.supabase.createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true }
    })
    : null;

  function requireClient() {
    if (!client) {
      throw new Error("Supabase is not configured. Set the project URL and anon key in js/config.js.");
    }
    return client;
  }

  async function unwrap(query) {
    const { data, error } = await query;
    if (error) throw error;
    return data;
  }

  function getPublicUrl(bucket, path) {
    const { data } = requireClient().storage.from(bucket).getPublicUrl(path);
    if (!data || !data.publicUrl) throw new Error("Could not create a public file URL.");
    return data.publicUrl;
  }

  function publicQuery(table, columns, filters) {
    let query = requireClient().from(table).select(columns);
    if (filters) query = filters(query);
    return unwrap(query);
  }

  window.DSCCSupabase = Object.freeze({
    client,
    isConfigured: Boolean(client),
    auth: Object.freeze({
      async login(email, password) {
        return unwrap(requireClient().auth.signInWithPassword({
          email: String(email || "").trim().toLowerCase(),
          password: String(password || "")
        }));
      },
      async logout() {
        return unwrap(requireClient().auth.signOut());
      }
    }),
    publicContent: Object.freeze({
      news() {
        return publicQuery("news", "id,title,summary,body,published_at", (query) =>
          query.eq("status", "published").order("published_at", { ascending: false }).limit(3));
      },
      announcements() {
        return publicQuery("announcements", "title,body,priority,status", (query) =>
          query.eq("status", "active").order("updated_at", { ascending: false }).limit(1));
      },
      activities() {
        return publicQuery("activities", "id,title,category,description,event_date", (query) =>
          query.eq("status", "published").order("event_date", { ascending: false, nullsFirst: false }));
      },
      gallery() {
        return publicQuery("gallery_items", "id,category,caption,media_type,image_url,video_url,image_path", (query) =>
          query.order("sort_order", { ascending: true }).order("created_at", { ascending: false }));
      },
      academicResources() {
        return publicQuery("academic_resources", "section,resource_type,title,file_url,status", (query) =>
          query.eq("status", "published").order("created_at", { ascending: false }));
      },
      pageContent() {
        return publicQuery("page_content", "key,value");
      },
      admissions() {
        return publicQuery("admissions", "id,title,content,image_url,target_grade,created_at", (query) =>
          query.order("created_at", { ascending: false }));
      }
    }),
    admissions: Object.freeze({
      list() {
        return unwrap(requireClient().from("admissions").select("*").order("created_at", { ascending: false }));
      },
      create(record) {
        return unwrap(requireClient().from("admissions").insert(record).select().single());
      },
      update(id, changes) {
        return unwrap(requireClient().from("admissions").update(changes).eq("id", id).select().single());
      },
      remove(id) {
        return unwrap(requireClient().from("admissions").delete().eq("id", id));
      }
    }),
    academics: Object.freeze({
      list() {
        return unwrap(requireClient().from("academics").select("*").order("created_at", { ascending: false }));
      },
      create(record) {
        return unwrap(requireClient().from("academics").insert(record).select().single());
      },
      update(id, changes) {
        return unwrap(requireClient().from("academics").update(changes).eq("id", id).select().single());
      },
      remove(id) {
        return unwrap(requireClient().from("academics").delete().eq("id", id));
      }
    }),
    storage: Object.freeze({
      async uploadAdmissionsMedia(file, folder) {
        if (!(file instanceof File)) throw new TypeError("Choose a file to upload.");
        const allowedTypes = ["image/jpeg", "image/png", "image/webp"];
        if (!allowedTypes.includes(file.type)) throw new Error("Use a JPEG, PNG, or WebP image.");
        if (file.size > 5 * 1024 * 1024) throw new Error("The image must be 5 MB or smaller.");

        const safeFolder = folder == null || folder === "" ? "" : String(folder)
          .split("/")
          .map((part) => part.trim())
          .filter(Boolean)
          .map((part) => part.replace(/[^a-zA-Z0-9_-]/g, "-"))
          .join("/") + "/";
        const extension = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[file.type];
        const path = safeFolder + crypto.randomUUID() + "." + extension;
        const { error } = await requireClient().storage.from("admissions-media").upload(path, file, {
          cacheControl: "3600",
          contentType: file.type,
          upsert: false
        });
        if (error) throw error;
        return { path, publicUrl: getPublicUrl("admissions-media", path) };
      },
      async removeAdmissionsMedia(path) {
        const { error } = await requireClient().storage.from("admissions-media").remove([path]);
        if (error) throw error;
        return true;
      }
    })
  });
})();
