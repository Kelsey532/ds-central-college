# D.S. Senanayake Central College, Mirigama: website and admin dashboard

Plain HTML, CSS and vanilla JavaScript. No build step. Works on GitHub Pages.
In production, staff authentication, dashboard content, and the audit trail are handled by Supabase.

## Local admin demo (not secure)

Without Supabase configured, the admin page runs as a browser-only demo:

- Username: `malith`
- Password: `malith123`
- Dashboard edits are saved only in the current browser's local storage.

This demo login is visible in the website's JavaScript and can be bypassed. It does not protect data and must not be used for a public or production website. Use the Supabase setup below before publishing the admin dashboard. Supabase mode uses real staff email/password accounts instead of these demo credentials.

## What is in the box

| Path | Purpose |
| --- | --- |
| `index.html`, `about.html`, `academics.html`, `activities.html`, `gallery.html`, `contact.html` | Public pages |
| `admin/login.html`, `admin/dashboard.html` | Staff portal |
| `css/style.css` | Design tokens, layout, all public components (admin reuses it) |
| `css/animations.css` | All motion, switched off for `prefers-reduced-motion` |
| `css/responsive.css` | Tablet and mobile rules |
| `css/admin.css` | Dashboard styles |
| `js/main.js` | Navigation, reveals, and loading of news, activities, gallery and page text |
| `js/statue.js` | Hero statue tilt, parallax and golden particles |
| `js/admin.js` | Login, dashboard modules |
| `js/config.js` | Shared site settings and legacy Supabase configuration fallback |
| `js/supabase-config.js` | Shared Supabase client, Auth, Admissions/Curriculum CRUD, and media uploads |
| `supabase/setup_master.sql` | Unified tables, roles, security rules, audit log, and storage buckets |
| `supabase/functions/create-staff-user/index.ts` | Secure Super-Admin-only staff account provisioning |
| `supabase/functions/manage-staff-user/index.ts` | Secure staff role, status, and deletion management |

## 1. Add the real images

The supplied official school emblem is included as a transparent-corner PNG:

Keep `images/school-emblem.png` as the high-resolution source. The headers use `images/school-emblem.webp`, and pages use the optimized `images/school-emblem-icon.png` favicon.

The hero uses the included optimized campus image. The legacy single-page version uses `images/statue/statue.webp`; replace the source image before regenerating its WebP version.

Optimized WebP artwork and a small PNG favicon are included so the full-resolution source images do not need to be downloaded for normal page views.

Other photos go in `images/school/`. Gallery items can use these site images or secure `https://` image URLs.

## 2. Set up Supabase (free plan is enough)

1. Create a project at supabase.com.
2. Open **SQL Editor**, paste all of `supabase/setup_master.sql`, and run it. The idempotent script includes the existing dashboard backend plus the Admissions, Academics, Admin Users, and `admissions-media` setup.
3. **Authentication > Users > Add user**: create the first administrator with a strong password you choose.
4. In the SQL Editor run (use that person's email):
   `update public.profiles set role = 'main_admin', active = true where email = 'THEIR_EMAIL';`
5. **Authentication > Sign In / Providers**: turn **off** "Allow new users to sign up".
6. **Authentication > URL Configuration**: set the Site URL to your published site.
7. **Project Settings > API**: replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` near the top of `js/supabase-config.js` with the Project URL and `anon` public key.
   Never paste the `service_role` key anywhere in this project.

## Create staff accounts from the dashboard

The **Manage Admins** dashboard section is visible only to Super Admins. It can create active Editor and Admin accounts with a temporary password, update roles and access, and delete other accounts. This requires the protected Supabase Edge Functions; static browser code must never receive the service-role key. Local demo mode cannot securely manage accounts.

1. Install and authenticate the Supabase CLI, then link the project with `supabase link --project-ref YOUR_PROJECT_REF`.
2. Ensure `SUPABASE_SERVICE_ROLE_KEY` is available to Edge Functions as a server-side secret. If it is not already provided by your project, add it through the Supabase Edge Function secrets settings or with `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY`. Never add it to `js/config.js`.
3. Set `ADMIN_ALLOWED_ORIGINS` to a comma-separated list of the exact HTTPS origins serving the site (for example `https://school.example.lk`). Do not use `*`. Include the exact development origin if testing locally.
4. Deploy both functions: `supabase functions deploy create-staff-user` and `supabase functions deploy manage-staff-user`. Keep JWT verification enabled.
5. Run the updated `supabase/setup_master.sql` to install the profile-write restrictions, guarded role-management RPCs, and unified content policies.
6. Configure the public URL and anon key in `js/supabase-config.js`; the functions use those values plus server-side secrets.

The functions validate the signed-in caller against an active `main_admin` profile for every account action. Supabase Auth handles password hashing; the dashboard never stores the temporary password. Self-management is blocked, and the final active Super Admin cannot be demoted, deactivated, or deleted.

## 3. Publish on GitHub Pages

Upload the folder contents to a repository, then Settings > Pages > deploy from the main branch.
Because the admin pages are static files, anyone can open `admin/login.html`; only signed-in, activated staff can do anything, because the database enforces it.

## Security design

- Production Supabase passwords and secret keys are never stored in the code. The local demo password above is hard-coded and public by design; the anon key is safe only because Row Level Security is on for every table.
- Roles are enforced in the database and protected Edge Functions, not the browser:
  - **Main admin (Super Admin)**: everything, including deleting content, managing users, and reading the full audit log.
  - **Editor**: create, edit, publish and unpublish content; add secure gallery image URLs and reorder gallery items. Cannot delete news, announcements or activities, cannot manage users.
- Accounts created from the dashboard are activated by the protected Edge Function. Accounts created manually in Supabase start inactive until a main admin activates them. Browser clients cannot directly update profiles; guarded server-side account management prevents self-management and protects the last active Super Admin.
- Sessions use Supabase Auth. Editor access ends after one hour (also enforced by database row-level security); main-admin access is checked against the active profile.
- Dashboard content changes are written to Supabase and cached in the browser. CRUD permissions are enforced by row-level security, and database triggers write the audit log.
- Gallery entries accept the included site images or `https://` image URLs. Supabase Storage has server-side size and MIME-type limits for a future upload interface.
- The audit log is filled by database triggers on every content, content-text and user change. It cannot be edited from the browser.
- Admissions and curriculum data use `admissions` and `academics`; browser access is exposed through `window.DSCCSupabase`. Uploads go to the public-read `admissions-media` bucket and writes remain enforced by RLS.
- Text from the database is always inserted with `textContent`, never as HTML. Public links and map embeds only accept `https`, `tel:`, `mailto:` and Google Maps embed addresses.

## Things to know

- **Manage Admins** requires deploying both protected staff-management Edge Functions and setting `ADMIN_ALLOWED_ORIGINS`. The local demo cannot securely create or manage accounts.
- The pages load the Supabase library from a CDN. For stricter security, pin an exact version and add a Subresource Integrity hash to the `<script>` tag in both admin pages.
- All school facts (history, vision, mission, principal's message, contacts, programmes) are `[PLACEHOLDER: …]` until the school supplies verified text. Fill them in under **Page content** and **Contact details**.
