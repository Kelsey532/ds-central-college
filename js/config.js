/*
 * Public site configuration.
 * The Supabase URL and ANON key are designed to be public (they are safe in a
 * static site) ONLY because Row Level Security on the database enforces who can
 * read and write. NEVER put a service-role key or any password in this file.
 */
window.DSCC_CONFIG = {
  supabaseUrl: "",      // [PLACEHOLDER: your Supabase project URL]
  supabaseAnonKey: "",  // [PLACEHOLDER: your Supabase anon (public) key]
  statueImage: "images/statue/statue.webp",
  statueFallback: "images/statue/statue-placeholder.svg"
};
