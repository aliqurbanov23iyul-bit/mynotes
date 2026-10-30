begin;
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '' check(char_length(display_name)<=80),
 avatar_url text check(avatar_url is null or (char_length(avatar_url)<=2048 and avatar_url ~ '^https://')),
 workspace_version bigint not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table private.admin_members(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create table public.notes(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,title text not null check(char_length(btrim(title)) between 1 and 120),content text not null check(char_length(content)<=10000),category text not null default 'Şəxsi' check(category in ('Şəxsi','Təhsil','İdeyalar','İş')),is_pinned boolean not null default false,legacy_import_key text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(user_id,legacy_import_key),unique(user_id,id));
create table public.tasks(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,title text not null check(char_length(btrim(title)) between 1 and 160),description text not null default '' check(char_length(description)<=3000),due_at timestamptz not null,status text not null default 'pending' check(status in ('pending','completed')),priority text not null default 'normal' check(priority in ('low','normal','high')),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.calendar_events(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,title text not null check(char_length(btrim(title)) between 1 and 160),description text not null default '' check(char_length(description)<=3000),starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),created_at timestamptz not null default now());
create table public.favorite_movies(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,tmdb_movie_id bigint check(tmdb_movie_id>0),catalog_key text check(char_length(catalog_key)<=100),status text not null check(status in ('favorite','watchlist')),created_at timestamptz not null default now(),check(num_nonnulls(tmdb_movie_id,catalog_key)=1),unique(user_id,tmdb_movie_id,status),unique(user_id,catalog_key,status));
create table public.ai_preferences(id uuid primary key default gen_random_uuid(),user_id uuid not null unique references auth.users(id) on delete cascade,preferred_model text not null default 'auto' check(preferred_model in ('auto','Gemini','Claude','Grok')),autopilot_enabled boolean not null default false,notes_access_enabled boolean not null default false,notifications_enabled boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.jarvis_jobs(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,source_note_id uuid,job_type text not null default 'prepare_material' check(job_type in ('prepare_material','review_plan')),scheduled_at timestamptz not null,status text not null default 'draft' check(status in ('draft','scheduled','cancelled','completed','failed')),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),foreign key(user_id,source_note_id) references public.notes(user_id,id) on delete cascade);
create table public.app_settings(id uuid primary key default gen_random_uuid(),setting_key text not null unique check(setting_key in ('featured_movie','ai_models','features')),setting_value jsonb not null check(octet_length(setting_value::text)<16000),updated_at timestamptz not null default now());
create table private.imports(user_id uuid primary key references auth.users(id) on delete cascade,imported_at timestamptz not null default now());
create table private.admin_audit(id bigint generated always as identity primary key,actor_id uuid,action text not null,target_id uuid,created_at timestamptz not null default now());
create index notes_owner_date on public.notes(user_id,is_pinned desc,updated_at desc);
create index tasks_owner_due on public.tasks(user_id,due_at);
create index events_owner_date on public.calendar_events(user_id,starts_at);
create index jobs_owner_date on public.jarvis_jobs(user_id,scheduled_at);
create index jobs_note on public.jarvis_jobs(user_id,source_note_id);
create index movies_owner on public.favorite_movies(user_id);
create function private.touch_updated() returns trigger language plpgsql set search_path='' as $$begin new.updated_at=now();return new;end$$;
create function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$begin insert into public.profiles(id,display_name) values(new.id,left(coalesce(new.raw_user_meta_data->>'display_name',''),80));insert into public.ai_preferences(user_id) values(new.id);return new;end$$;
create trigger create_profile after insert on auth.users for each row execute function private.new_user();
insert into public.profiles(id,display_name) select id,left(coalesce(raw_user_meta_data->>'display_name',''),80) from auth.users on conflict do nothing;
insert into public.ai_preferences(user_id) select id from auth.users on conflict do nothing;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.admin_members where user_id=(select auth.uid()))$$;
revoke all on function public.is_admin() from public,anon;
grant execute on function public.is_admin() to authenticated;
alter table public.profiles enable row level security;
create policy profiles_self_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_self_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
revoke all on public.profiles from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(display_name,avatar_url) on public.profiles to authenticated;
-- Separate policies per operation on every owner-scoped table.
do $$declare t text;begin foreach t in array array['notes','tasks','calendar_events','favorite_movies','ai_preferences','jarvis_jobs'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 execute format('create policy %I on public.%I for select to authenticated using(user_id=(select auth.uid()))',t||'_own_read',t);
 execute format('create policy %I on public.%I for insert to authenticated with check(user_id=(select auth.uid()))',t||'_own_insert',t);
 execute format('create policy %I on public.%I for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()))',t||'_own_update',t);
 execute format('create policy %I on public.%I for delete to authenticated using(user_id=(select auth.uid()))',t||'_own_delete',t);
 end loop;
 foreach t in array array['profiles','notes','tasks','ai_preferences','jarvis_jobs','app_settings'] loop execute format('create trigger touch_updated before update on public.%I for each row execute function private.touch_updated()',t);end loop;
end$$;
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon,authenticated;
grant select on public.app_settings to authenticated;
create policy public_settings_read on public.app_settings for select to authenticated using(true);
-- Settings hold public feature configuration only, never secrets.
insert into public.app_settings(setting_key,setting_value) values('featured_movie','"interstellar"'),('features','{"notes":true,"calendar":true,"jarvis":false}'),('ai_models','{"Gemini":{"style":"Balanslı","limit":100},"Claude":{"style":"Balanslı","limit":100},"Grok":{"style":"Balanslı","limit":100}}');
revoke all on all tables in schema private from public,anon,authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
commit;
