-- =====================================================================
-- D.S. Senanayake Central College, Mirigama : Supabase backend schema
-- Legacy base schema retained for reference. Use setup_master.sql for the
-- current deployment; this file does not include all current tables/RPCs.
-- Do not apply this file instead of setup_master.sql.
--
-- SECURITY MODEL
--  * Every permission is enforced HERE (Row Level Security + triggers),
--    not in the browser. Hiding a button in the dashboard is only a convenience.
--  * Roles:  main_admin  = full control, manages users, reads the full audit log
--            editor      = creates/edits/publishes content, uploads images
--  * New sign-ups get an INACTIVE editor profile. A main admin must activate them.
--  * The audit log is written by database triggers, so it cannot be skipped
--    or edited from the browser.
-- =====================================================================

-- ---------- Profiles (one row per admin user) ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  role        text not null default 'editor' check (role in ('main_admin', 'editor')),
  active      boolean not null default false,
  created_at  timestamptz not null default now()
);

-- Role helpers. SECURITY DEFINER so they can read profiles without recursive RLS.
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active
      and (
        p.role = 'main_admin'
        or (
          p.role = 'editor'
          and exists (
            select 1
            from auth.sessions s
            where s.id = nullif(auth.jwt()->>'session_id', '')::uuid
              and s.user_id = auth.uid()
              and s.created_at > now() - interval '1 hour'
          )
        )
      )
  );
$$;

create or replace function public.is_main_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'main_admin');
$$;

-- Auto-create an INACTIVE editor profile whenever an auth user is created/invited.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Content tables ----------
create table if not exists public.news (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (char_length(title) between 1 and 200),
  summary      text check (char_length(summary) <= 500),
  body         text check (char_length(body) <= 20000),
  status       text not null default 'draft' check (status in ('draft', 'published')),
  published_at timestamptz,
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id),
  updated_at   timestamptz not null default now()
);

create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 1 and 200),
  body        text check (char_length(body) <= 5000),
  priority    text not null default 'Notice' check (priority in ('Notice', 'Important', 'Urgent')),
  status      text not null default 'active' check (status in ('active', 'archived')),
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);
alter table public.announcements
  add column if not exists priority text not null default 'Notice'
  check (priority in ('Notice', 'Important', 'Urgent'));

create table if not exists public.activities (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 1 and 200),
  category    text not null default 'Events'
              check (category in ('Sports', 'Clubs', 'Societies', 'Events', 'Extra-curricular')),
  description text check (char_length(description) <= 5000),
  event_date  date,
  status      text not null default 'draft' check (status in ('draft', 'published')),
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);

create table if not exists public.gallery_items (
  id          uuid primary key default gen_random_uuid(),
  category    text not null default 'General' check (char_length(category) between 1 and 60),
  caption     text check (char_length(caption) <= 300),
  media_type  text not null default 'image' check (media_type in ('image', 'video')),
  image_path  text,   -- path inside the 'gallery' storage bucket (for deletes)
  image_url   text,
  video_url   text,   -- approved embeds only (YouTube / Vimeo)
  sort_order  integer not null default 0,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now(),
  constraint gallery_media_valid check (
    (media_type = 'image' and image_url ~ '^https://' and video_url is null)
    or
    (media_type = 'video' and video_url ~ '^https://(www\.youtube(-nocookie)?\.com/embed/|player\.vimeo\.com/video/)')
  )
);

-- Editable text for About / Academics pages and Contact details (key/value)
create table if not exists public.page_content (
  key         text primary key,
  page        text not null check (page in ('about', 'academics', 'contact')),
  label       text not null,
  value       text not null default '' check (char_length(value) <= 20000),
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);

-- Seed editable fields with clearly marked placeholders (no invented facts).
insert into public.page_content (key, page, label, value) values
  ('about.history',           'about',     'School history',            '[PLACEHOLDER: Verified School History]'),
  ('about.vision',            'about',     'Vision',                    '[PLACEHOLDER: Verified Vision statement]'),
  ('about.mission',           'about',     'Mission',                   '[PLACEHOLDER: Verified Mission statement]'),
  ('about.principal_message', 'about',     'Principal''s message',      '[PLACEHOLDER: Verified Principal''s message]'),
  ('about.identity',          'about',     'School identity',           '[PLACEHOLDER: Verified school motto, crest, colours and song]'),
  ('academics.intro',         'academics', 'Overview',                  '[PLACEHOLDER: Verified academic overview]'),
  ('academics.sections',      'academics', 'Academic sections',         '[PLACEHOLDER: Verified list of academic sections / grade levels]'),
  ('academics.subjects',      'academics', 'Subjects',                  '[PLACEHOLDER: Verified subjects offered]'),
  ('academics.programs',      'academics', 'Educational programmes',    '[PLACEHOLDER: Verified educational programmes]'),
  ('contact.address',         'contact',   'Address',                   '[PLACEHOLDER: Verified address]'),
  ('contact.phone',           'contact',   'Phone',                     '[PLACEHOLDER: Verified phone]'),
  ('contact.email',           'contact',   'Email',                     '[PLACEHOLDER: Verified email]'),
  ('contact.facebook',        'contact',   'Social media link (https)', ''),
  ('contact.map_url',         'contact',   'Google Maps embed URL',     '')
on conflict (key) do nothing;

-- Audit log (append-only)
create table if not exists public.audit_log (
  id          bigint generated always as identity primary key,
  user_id     uuid,
  user_email  text,
  action      text not null,
  table_name  text not null,
  record_id   text,
  details     jsonb,
  created_at  timestamptz not null default now()
);

-- ---------- Triggers: stamp authorship + write audit log ----------
create or replace function public.stamp_row() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
  end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  -- published_at is set by the database, never trusted from the browser
  if tg_table_name = 'news' then
    if new.status = 'published' and (tg_op = 'INSERT' or old.status <> 'published' or old.published_at is null) then
      new.published_at := now();
    elsif new.status = 'draft' then
      new.published_at := null;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.write_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  who text;
begin
  r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  select email into who from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, user_email, action, table_name, record_id, details)
  values (
    auth.uid(), who, tg_op, tg_table_name,
    coalesce(r->>'id', r->>'key'),
    jsonb_build_object('title', coalesce(r->>'title', r->>'caption', r->>'label', r->>'email'),
                       'status', r->>'status', 'role', r->>'role', 'active', r->>'active')
  );
  return null;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['news', 'announcements', 'activities', 'gallery_items', 'page_content'] loop
    execute format('drop trigger if exists stamp_%1$s on public.%1$s', t);
    execute format('create trigger stamp_%1$s before insert or update on public.%1$s for each row execute function public.stamp_row()', t);
  end loop;
  foreach t in array array['news', 'announcements', 'activities', 'gallery_items', 'page_content', 'profiles'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update or delete on public.%1$s for each row execute function public.write_audit()', t);
  end loop;
end $$;

-- page_content has no created_by column; make stamp_row tolerate that.
alter table public.page_content add column if not exists created_by uuid;

-- ---------- Row Level Security ----------
alter table public.profiles       enable row level security;
alter table public.news           enable row level security;
alter table public.announcements  enable row level security;
alter table public.activities     enable row level security;
alter table public.gallery_items  enable row level security;
alter table public.page_content   enable row level security;
alter table public.audit_log      enable row level security;

-- profiles: you can read your own; main admins read and manage everyone else (never themselves, to avoid lock-out)
drop policy if exists profiles_self_read   on public.profiles;
drop policy if exists profiles_admin_read  on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_self_read  on public.profiles for select using (id = auth.uid());
create policy profiles_admin_read on public.profiles for select using (public.is_main_admin());
create policy profiles_admin_write on public.profiles for update
  using (public.is_main_admin() and id <> auth.uid())
  with check (public.is_main_admin() and id <> auth.uid());

-- news
drop policy if exists news_public_read   on public.news;
drop policy if exists news_staff_read    on public.news;
drop policy if exists news_staff_insert  on public.news;
drop policy if exists news_staff_update  on public.news;
drop policy if exists news_admin_delete  on public.news;
create policy news_public_read  on public.news for select using (status = 'published');
create policy news_staff_read   on public.news for select using (public.is_staff());
create policy news_staff_insert on public.news for insert with check (public.is_staff());
create policy news_staff_update on public.news for update using (public.is_staff()) with check (public.is_staff());
create policy news_admin_delete on public.news for delete using (public.is_main_admin());

-- announcements (public sees only active ones)
drop policy if exists ann_public_read  on public.announcements;
drop policy if exists ann_staff_read   on public.announcements;
drop policy if exists ann_staff_insert on public.announcements;
drop policy if exists ann_staff_update on public.announcements;
drop policy if exists ann_admin_delete on public.announcements;
create policy ann_public_read  on public.announcements for select using (status = 'active');
create policy ann_staff_read   on public.announcements for select using (public.is_staff());
create policy ann_staff_insert on public.announcements for insert with check (public.is_staff());
create policy ann_staff_update on public.announcements for update using (public.is_staff()) with check (public.is_staff());
create policy ann_admin_delete on public.announcements for delete using (public.is_main_admin());

-- activities
drop policy if exists act_public_read  on public.activities;
drop policy if exists act_staff_read   on public.activities;
drop policy if exists act_staff_insert on public.activities;
drop policy if exists act_staff_update on public.activities;
drop policy if exists act_admin_delete on public.activities;
create policy act_public_read  on public.activities for select using (status = 'published');
create policy act_staff_read   on public.activities for select using (public.is_staff());
create policy act_staff_insert on public.activities for insert with check (public.is_staff());
create policy act_staff_update on public.activities for update using (public.is_staff()) with check (public.is_staff());
create policy act_admin_delete on public.activities for delete using (public.is_main_admin());

-- gallery: public read; staff (including editors) manage
drop policy if exists gal_public_read  on public.gallery_items;
drop policy if exists gal_staff_insert on public.gallery_items;
drop policy if exists gal_staff_update on public.gallery_items;
drop policy if exists gal_staff_delete on public.gallery_items;
create policy gal_public_read  on public.gallery_items for select using (true);
create policy gal_staff_insert on public.gallery_items for insert with check (public.is_staff());
create policy gal_staff_update on public.gallery_items for update using (public.is_staff()) with check (public.is_staff());
create policy gal_staff_delete on public.gallery_items for delete using (public.is_staff());

-- page_content: public read, staff update. Rows are seeded above; editors cannot add or delete keys.
drop policy if exists pc_public_read  on public.page_content;
drop policy if exists pc_staff_update on public.page_content;
create policy pc_public_read  on public.page_content for select using (true);
create policy pc_staff_update on public.page_content for update using (public.is_staff()) with check (public.is_staff());

-- audit_log: main admins read all, staff read their own. Nobody can write/update/delete from the browser.
drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select
  using (public.is_main_admin() or user_id = auth.uid());

-- ---------- Storage: public 'gallery' bucket with server-side limits ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gallery', 'gallery', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists gallery_public_read  on storage.objects;
drop policy if exists gallery_staff_insert on storage.objects;
drop policy if exists gallery_staff_delete on storage.objects;
create policy gallery_public_read  on storage.objects for select using (bucket_id = 'gallery');
create policy gallery_staff_insert on storage.objects for insert with check (bucket_id = 'gallery' and public.is_staff());
create policy gallery_staff_delete on storage.objects for delete using (bucket_id = 'gallery' and public.is_staff());

-- ---------- Grants (RLS still decides what each row allows) ----------
grant usage on schema public to anon, authenticated;
grant select on public.news, public.announcements, public.activities, public.gallery_items, public.page_content to anon;
grant select, insert, update, delete on public.news, public.announcements, public.activities, public.gallery_items to authenticated;
grant select, update on public.page_content to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.audit_log to authenticated;

-- =====================================================================
-- AFTER RUNNING THIS FILE: create the first Main Admin
--  1. Supabase > Authentication > Users > "Add user" (enter email + a strong password you choose).
--  2. Then run, with that person's email:
--       update public.profiles set role = 'main_admin', active = true where email = 'PRINCIPAL_OR_ADMIN_EMAIL';
--  3. Supabase > Authentication > Sign In / Providers > turn OFF "Allow new users to sign up".
--  4. Supabase > Authentication > URL Configuration: add your site URL and the admin/index.html URL
--     as Redirect URLs so password reset links work.
-- =====================================================================
