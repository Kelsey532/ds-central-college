-- =====================================================================
-- D.S. Senanayake Central College, Mirigama : Supabase backend schema
-- Run this whole file once in: Supabase Dashboard > SQL Editor.
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

-- Account-role changes are only accepted from the service-role Edge Function.
-- Serialize changes so concurrent requests cannot remove the last active super admin.
create or replace function public.manage_staff_profile(
  p_actor_id uuid,
  p_target_id uuid,
  p_role text,
  p_active boolean
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  target public.profiles%rowtype;
  active_admin_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only the staff management service may update account roles.';
  end if;
  if p_actor_id is null or p_target_id is null or p_actor_id = p_target_id then
    raise exception 'A super admin cannot change their own account.';
  end if;
  if p_role is null or p_role not in ('main_admin', 'editor') or p_active is null then
    raise exception 'A valid role and account status are required.';
  end if;

  perform pg_advisory_xact_lock(1720318123::bigint);
  if not exists (
    select 1 from public.profiles
    where id = p_actor_id and active and role = 'main_admin'
  ) then
    raise exception 'Only an active super admin can manage staff accounts.';
  end if;
  select * into target from public.profiles where id = p_target_id for update;
  if not found then
    raise exception 'The selected staff account no longer exists.';
  end if;

  if target.active and target.role = 'main_admin'
     and (not p_active or p_role <> 'main_admin') then
    select count(*) into active_admin_count
      from public.profiles where active and role = 'main_admin';
    if active_admin_count <= 1 then
      raise exception 'Cannot remove the last active super admin.';
    end if;
  end if;

  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  update public.profiles set role = p_role, active = p_active where id = p_target_id;
  select * into target from public.profiles where id = p_target_id;
  return to_jsonb(target);
end;
$$;
revoke all on function public.manage_staff_profile(uuid, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.manage_staff_profile(uuid, uuid, text, boolean) to service_role;

create or replace function public.activate_staff_profile(
  p_actor_id uuid,
  p_target_id uuid,
  p_username text,
  p_role text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  target public.profiles%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only the staff management service may activate accounts.';
  end if;
  if p_actor_id is null or p_target_id is null or p_actor_id = p_target_id then
    raise exception 'A super admin cannot create an account for themselves.';
  end if;
  if p_username is null or char_length(trim(p_username)) not between 1 and 120 then
    raise exception 'Enter a username with no more than 120 characters.';
  end if;
  if p_role is null or p_role not in ('main_admin', 'editor') then
    raise exception 'Choose Admin or Editor as the account role.';
  end if;

  perform pg_advisory_xact_lock(1720318123::bigint);
  if not exists (
    select 1 from public.profiles
    where id = p_actor_id and active and role = 'main_admin'
  ) then
    raise exception 'Only an active super admin can create staff accounts.';
  end if;
  select * into target from public.profiles where id = p_target_id for update;
  if not found or target.active then
    raise exception 'The new staff profile is missing or already active.';
  end if;

  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  update public.profiles
    set full_name = trim(p_username), role = p_role, active = true
    where id = p_target_id;
  select * into target from public.profiles where id = p_target_id;
  return to_jsonb(target);
end;
$$;
revoke all on function public.activate_staff_profile(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.activate_staff_profile(uuid, uuid, text, text) to service_role;

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
              check (category in ('Sports', 'Clubs', 'Societies', 'Achievements', 'Events', 'Extra-curricular')),
  description text check (char_length(description) <= 5000),
  event_date  date,
  status      text not null default 'draft' check (status in ('draft', 'published')),
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);
alter table public.activities drop constraint if exists activities_category_check;
alter table public.activities
  add constraint activities_category_check
  check (category in ('Sports', 'Clubs', 'Societies', 'Achievements', 'Events', 'Extra-curricular'));

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

-- Section-targeted syllabi, exam notices, and study materials.
create table if not exists public.academic_resources (
  id            uuid primary key default gen_random_uuid(),
  section       text not null check (section in ('junior_secondary', 'senior_secondary', 'advanced_level')),
  resource_type text not null check (resource_type in ('syllabus', 'exam_notice', 'study_material')),
  title         text not null check (char_length(title) between 1 and 200),
  file_url      text not null check (file_url ~ '^https://[^/[:space:]]+([/?#][^[:space:]]*)?$'),
  file_path     text,
  status        text not null default 'draft' check (status in ('draft', 'published')),
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_by    uuid references auth.users(id),
  updated_at    timestamptz not null default now(),
  constraint academic_resource_file_section check (
    file_path is null or file_path like section || '/%'
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
  ('academics.sections',      'academics', 'Academic sections',         'Junior Secondary (Grades 6 - 9); Senior Secondary (Grades 10 - 11 / O/L); Advanced Level (Grades 12 - 13 / A/L).'),
  ('academics.subjects',      'academics', 'Subjects',                  '[PLACEHOLDER: Verified subjects offered]'),
  ('academics.programs',      'academics', 'Educational programmes',    '[PLACEHOLDER: Verified educational programmes]'),
  ('academics.performance',   'academics', 'Student performance',       '[PLACEHOLDER: Verified student performance and examination results]'),
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
  foreach t in array array['news', 'announcements', 'activities', 'gallery_items', 'academic_resources', 'page_content'] loop
    execute format('drop trigger if exists stamp_%1$s on public.%1$s', t);
    execute format('create trigger stamp_%1$s before insert or update on public.%1$s for each row execute function public.stamp_row()', t);
  end loop;
  foreach t in array array['news', 'announcements', 'activities', 'gallery_items', 'academic_resources', 'page_content', 'profiles'] loop
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
alter table public.academic_resources enable row level security;
alter table public.page_content   enable row level security;
alter table public.audit_log      enable row level security;

-- Profiles are readable by the owner and super admins. Writes use the guarded
-- staff-management Edge Functions, never direct browser mutations.
drop policy if exists profiles_self_read   on public.profiles;
drop policy if exists profiles_admin_read  on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_self_read  on public.profiles for select using (id = auth.uid());
create policy profiles_admin_read on public.profiles for select using (public.is_main_admin());

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

-- Academic resources: public readers only see published materials; staff manage.
drop policy if exists academic_resources_public_read on public.academic_resources;
drop policy if exists academic_resources_staff_read on public.academic_resources;
drop policy if exists academic_resources_staff_insert on public.academic_resources;
drop policy if exists academic_resources_staff_update on public.academic_resources;
drop policy if exists academic_resources_admin_delete on public.academic_resources;
create policy academic_resources_public_read on public.academic_resources for select using (status = 'published');
create policy academic_resources_staff_read on public.academic_resources for select using (public.is_staff());
create policy academic_resources_staff_insert on public.academic_resources for insert with check (public.is_staff());
create policy academic_resources_staff_update on public.academic_resources for update using (public.is_staff()) with check (public.is_staff());
create policy academic_resources_admin_delete on public.academic_resources for delete using (public.is_main_admin());

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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('academic-resources', 'academic-resources', true, 20971520, array['application/pdf'])
on conflict (id) do update
  set public = true, file_size_limit = 20971520, allowed_mime_types = array['application/pdf'];

drop policy if exists academic_resources_files_public_read on storage.objects;
drop policy if exists academic_resources_files_staff_insert on storage.objects;
drop policy if exists academic_resources_files_staff_delete on storage.objects;
create policy academic_resources_files_public_read on storage.objects for select
  using (bucket_id = 'academic-resources');
create policy academic_resources_files_staff_insert on storage.objects for insert
  with check (
    bucket_id = 'academic-resources'
    and public.is_staff()
    and split_part(name, '/', 1) in ('junior_secondary', 'senior_secondary', 'advanced_level')
  );
create policy academic_resources_files_staff_delete on storage.objects for delete
  using (bucket_id = 'academic-resources' and public.is_staff());

-- ---------- Grants (RLS still decides what each row allows) ----------
grant usage on schema public to anon, authenticated;
grant select on public.news, public.announcements, public.activities, public.gallery_items, public.academic_resources, public.page_content to anon;
grant select, insert, update, delete on public.news, public.announcements, public.activities, public.gallery_items, public.academic_resources to authenticated;
grant select, update on public.page_content to authenticated;
grant select on public.profiles to authenticated;
grant select on public.audit_log to authenticated;

-- =====================================================================
-- AFTER RUNNING THIS FILE: create the first Main Admin
--  1. Supabase > Authentication > Users > "Add user" (enter email + a strong password you choose).
--  2. Then run, with that person's email:
--       update public.profiles set role = 'main_admin', active = true where email = 'PRINCIPAL_OR_ADMIN_EMAIL';
--  3. Supabase > Authentication > Sign In / Providers > turn OFF "Allow new users to sign up".
--  4. Supabase > Authentication > URL Configuration: add your site URL and the admin/login.html URL
--     as Redirect URLs for Supabase Auth.
-- =====================================================================

-- ---------- Unified admissions, curriculum, and admin access ----------
create table if not exists public.admissions (
  id uuid primary key default gen_random_uuid(),
  title text,
  content text,
  image_url text,
  target_grade text,
  created_at timestamptz not null default now()
);

create table if not exists public.academics (
  id uuid primary key default gen_random_uuid(),
  grade_category text not null
    check (grade_category in ('Junior Secondary', 'Senior Secondary', 'Advanced Level')),
  subject text,
  syllabus_url text,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null check (role in ('Super Admin', 'Admin', 'Editor')),
  created_at timestamptz not null default now()
);

create or replace function public.is_master_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admin_users au
    join public.profiles p on p.id = au.id
    where au.id = auth.uid()
      and au.role = 'Super Admin'
      and p.active
  );
$$;
revoke all on function public.is_master_super_admin() from public, anon;
grant execute on function public.is_master_super_admin() to authenticated;

create or replace function public.has_admissions_write_access()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admin_users au
    join public.profiles p on p.id = au.id
    where au.id = auth.uid()
      and p.active
      and au.role in ('Admin', 'Super Admin')
  );
$$;
revoke all on function public.has_admissions_write_access() from public, anon;
grant execute on function public.has_admissions_write_access() to authenticated;

create or replace function public.sync_admin_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.admin_users (id, email, role)
  values (
    new.id,
    new.email,
    case when new.role = 'main_admin' then 'Super Admin' else 'Editor' end
  )
  on conflict (id) do update
    set email = excluded.email, role = excluded.role;
  return new;
end;
$$;

drop trigger if exists sync_admin_user_profile on public.profiles;
create trigger sync_admin_user_profile
  after insert or update of email, role on public.profiles
  for each row execute function public.sync_admin_user_profile();
revoke all on function public.sync_admin_user_profile() from public, anon, authenticated;

insert into public.admin_users (id, email, role)
select id, email, case when role = 'main_admin' then 'Super Admin' else 'Editor' end
from public.profiles
on conflict (id) do update
  set email = excluded.email, role = excluded.role;

create or replace function public.guard_admin_user_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  affected_id uuid;
  active_super_admins integer;
begin
  affected_id := old.id;
  if old.role = 'Super Admin'
     and (tg_op = 'DELETE' or new.role <> 'Super Admin') then
    if auth.uid() = affected_id then
      raise exception 'A super admin cannot change or delete their own account.';
    end if;
    select count(*) into active_super_admins
      from public.admin_users au
      join public.profiles p on p.id = au.id
      where au.role = 'Super Admin' and p.active and au.id <> affected_id;
    if active_super_admins = 0 and exists (
      select 1 from public.profiles where id = affected_id and active
    ) then
      raise exception 'Cannot remove the last active super admin.';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_admin_user_changes on public.admin_users;
create trigger guard_admin_user_changes
  before update or delete on public.admin_users
  for each row execute function public.guard_admin_user_changes();
revoke all on function public.guard_admin_user_changes() from public, anon, authenticated;

alter table public.admissions enable row level security;
alter table public.academics enable row level security;
alter table public.admin_users enable row level security;

drop policy if exists admissions_public_read on public.admissions;
drop policy if exists admissions_admin_insert on public.admissions;
drop policy if exists admissions_admin_update on public.admissions;
drop policy if exists admissions_admin_delete on public.admissions;
create policy admissions_public_read on public.admissions
  for select to anon, authenticated using (true);
create policy admissions_admin_insert on public.admissions
  for insert to authenticated with check (public.has_admissions_write_access());
create policy admissions_admin_update on public.admissions
  for update to authenticated using (public.has_admissions_write_access())
  with check (public.has_admissions_write_access());
create policy admissions_admin_delete on public.admissions
  for delete to authenticated using (public.has_admissions_write_access());

drop policy if exists academics_public_read on public.academics;
drop policy if exists academics_admin_insert on public.academics;
drop policy if exists academics_admin_update on public.academics;
drop policy if exists academics_admin_delete on public.academics;
create policy academics_public_read on public.academics
  for select to anon, authenticated using (true);
create policy academics_admin_insert on public.academics
  for insert to authenticated with check (public.has_admissions_write_access());
create policy academics_admin_update on public.academics
  for update to authenticated using (public.has_admissions_write_access())
  with check (public.has_admissions_write_access());
create policy academics_admin_delete on public.academics
  for delete to authenticated using (public.has_admissions_write_access());

drop policy if exists admin_users_super_admin_read on public.admin_users;
drop policy if exists admin_users_super_admin_insert on public.admin_users;
drop policy if exists admin_users_super_admin_update on public.admin_users;
drop policy if exists admin_users_super_admin_delete on public.admin_users;
create policy admin_users_super_admin_read on public.admin_users
  for select to authenticated using (public.is_master_super_admin());
create policy admin_users_super_admin_insert on public.admin_users
  for insert to authenticated with check (public.is_master_super_admin());
create policy admin_users_super_admin_update on public.admin_users
  for update to authenticated using (public.is_master_super_admin())
  with check (public.is_master_super_admin());
create policy admin_users_super_admin_delete on public.admin_users
  for delete to authenticated using (public.is_master_super_admin());

grant select on public.admissions, public.academics to anon, authenticated;
grant insert, update, delete on public.admissions, public.academics to authenticated;
grant select, insert, update, delete on public.admin_users to authenticated;

-- Public media is readable by visitors; writes require an active Admin or
-- Super Admin profile represented in admin_users.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('admissions-media', 'admissions-media', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists admissions_media_public_read on storage.objects;
drop policy if exists admissions_media_admin_insert on storage.objects;
drop policy if exists admissions_media_admin_update on storage.objects;
drop policy if exists admissions_media_admin_delete on storage.objects;
create policy admissions_media_public_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'admissions-media');
create policy admissions_media_admin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'admissions-media' and public.has_admissions_write_access());
create policy admissions_media_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'admissions-media' and public.has_admissions_write_access())
  with check (bucket_id = 'admissions-media' and public.has_admissions_write_access());
create policy admissions_media_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'admissions-media' and public.has_admissions_write_access());
