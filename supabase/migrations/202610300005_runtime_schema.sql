begin;
-- Additive only: existing personal rows are not removed or rewritten.
alter table public.notes add column ai_analysis_allowed boolean not null default false;
alter table public.jarvis_jobs drop constraint jarvis_jobs_status_check;
alter table public.jarvis_jobs add constraint jarvis_jobs_status_check check(status in ('draft','scheduled','processing','retry','cancelled','completed','failed'));
alter table public.jarvis_jobs add column source_updated_at timestamptz;
alter table public.jarvis_jobs add column attempts integer not null default 0 check(attempts between 0 and 3);
alter table public.jarvis_jobs add column lease_until timestamptz;
alter table public.jarvis_jobs add column lease_token uuid;
alter table public.jarvis_jobs add column last_error text;
create unique index jobs_dedupe on public.jarvis_jobs(user_id,source_note_id,source_updated_at,scheduled_at,job_type);
alter table public.ai_preferences alter column notifications_enabled set default false;
-- Clients may cancel work, but cannot fabricate completed jobs or execution fields.
revoke insert,update,delete on public.jarvis_jobs from authenticated;
grant update(status) on public.jarvis_jobs to authenticated;
create policy jobs_cancel_only on public.jarvis_jobs as restrictive for update to authenticated using(status in ('draft','scheduled','retry')) with check(status='cancelled');
create table public.ai_policy(user_id uuid primary key references auth.users(id) on delete cascade,paid_consent boolean not null default false,notification_consent boolean not null default false,allow_fallback boolean not null default false,memory_enabled boolean not null default false,daily_usd numeric(12,6) not null default 0 check(daily_usd between 0 and 100),monthly_usd numeric(12,6) not null default 0 check(monthly_usd between 0 and 1000),daily_requests integer not null default 0 check(daily_requests between 0 and 1000),monthly_requests integer not null default 0 check(monthly_requests between 0 and 10000),timezone text not null default 'Asia/Baku' check(timezone in ('Asia/Baku','Europe/Istanbul','UTC')),daily_briefing boolean not null default false,weekly_summary boolean not null default false,push_enabled boolean not null default false,movie_notifications boolean not null default false,updated_at timestamptz not null default now());
create table public.conversations(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,title text not null default 'Yeni söhbət' check(char_length(title) between 1 and 120),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(user_id,id));
create table public.ai_requests(id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,conversation_id uuid,source_note_id uuid,cancel_requested boolean not null default false,status text not null default 'pending' check(status in ('pending','completed','failed','cancelled')),created_at timestamptz not null default now(),foreign key(user_id,conversation_id) references public.conversations(user_id,id) on delete cascade,foreign key(user_id,source_note_id) references public.notes(user_id,id) on delete cascade);
create table public.chat_messages(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,conversation_id uuid not null,request_id uuid references public.ai_requests(id) on delete set null,role text not null check(role in ('user','assistant')),content text not null check(char_length(content) between 1 and 120000),provider text,created_at timestamptz not null default now(),foreign key(user_id,conversation_id) references public.conversations(user_id,id) on delete cascade,unique(request_id,role));
create table public.ai_usage(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,request_id uuid not null,provider text not null,model text not null,kind text not null check(kind in ('chat','analysis','prepare')),input_tokens bigint,output_tokens bigint,reserved_usd numeric(16,8) not null check(reserved_usd>=0),cost_usd numeric(16,8),status text not null default 'reserved' check(status in ('reserved','completed','uncertain','failed')),created_at timestamptz not null default now(),finished_at timestamptz);
create index usage_owner_date on public.ai_usage(user_id,created_at);
create table public.ai_memory(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,label text not null check(char_length(label) between 1 and 80),content text not null check(char_length(content) between 1 and 2000),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.jarvis_proposals(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,note_id uuid not null,source_updated_at timestamptz not null,summary text not null check(char_length(summary)<=3000),suggested_time text,uncertainty text not null,confirmed boolean not null default false,created_at timestamptz not null default now(),foreign key(user_id,note_id) references public.notes(user_id,id) on delete cascade);
create table public.prepared_materials(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,job_id uuid not null unique references public.jarvis_jobs(id) on delete cascade,title text not null,content text not null,source_mode text not null default 'model_knowledge' check(source_mode='model_knowledge'),created_at timestamptz not null default now());
create table public.user_notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,kind text not null,title text not null,body text not null,dedupe_key text not null,is_read boolean not null default false,created_at timestamptz not null default now(),push_status text not null default 'pending' check(push_status in ('pending','sent','unsupported','failed')),unique(user_id,dedupe_key));
create table public.push_subscriptions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,endpoint text not null unique,p256dh text not null,auth text not null,created_at timestamptz not null default now());
create index messages_owner on public.chat_messages(user_id,conversation_id,created_at);
create index notifications_owner on public.user_notifications(user_id,created_at desc);
-- Anonymous financial totals survive account deletion, without user IDs or message content.
create table private.usage_totals(id uuid primary key,provider text not null,input_tokens bigint,output_tokens bigint,reserved_usd numeric(16,8) not null,cost_usd numeric(16,8),status text not null default 'reserved',created_at timestamptz not null default now());
create table private.provider_config(provider text primary key check(provider in ('Gemini','Claude','Grok')),enabled boolean not null default false,model text not null default '',endpoint text not null default '',input_per_million numeric(12,6),output_per_million numeric(12,6),context_tokens integer not null default 0,max_output_tokens integer not null default 0,capabilities text[] not null default '{}',updated_at timestamptz not null default now(),check(input_per_million>=0),check(output_per_million>=0));
insert into private.provider_config(provider) values('Gemini'),('Claude'),('Grok');
create table private.runtime_config(id boolean primary key default true check(id),ai_enabled boolean not null default false,automation_enabled boolean not null default false,default_provider text not null default 'auto',global_daily_usd numeric not null default 0 check(global_daily_usd between 0 and 10000),global_monthly_usd numeric not null default 0 check(global_monthly_usd between 0 and 100000),max_attempts integer not null default 2 check(max_attempts between 1 and 3),featured_tmdb_id bigint check(featured_tmdb_id>0),movie_automatic boolean not null default true);
insert into private.runtime_config(id) values(true);
create table private.rate_buckets(user_id uuid not null references auth.users(id) on delete cascade,bucket text not null,window_at timestamptz not null,hits integer not null,primary key(user_id,bucket,window_at));
create table private.external_cache(cache_key text primary key,value jsonb not null,expires_at timestamptz not null);
create table private.system_events(id bigint generated always as identity primary key,component text not null,code text not null,created_at timestamptz not null default now());
do $$declare t text;begin
 foreach t in array array['ai_policy','conversations','ai_memory'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 execute format('create policy owner_access on public.%I for all to authenticated using(user_id=(select auth.uid()) and (select public.account_allowed())) with check(user_id=(select auth.uid()) and (select public.account_allowed()))',t);end loop;
 foreach t in array array['ai_requests','chat_messages','ai_usage','jarvis_proposals','prepared_materials','user_notifications','push_subscriptions'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy owner_read on public.%I for select to authenticated using(user_id=(select auth.uid()) and (select public.account_allowed()))',t);end loop;
end$$;
grant update(cancel_requested) on public.ai_requests to authenticated;
create policy cancel_request on public.ai_requests for update to authenticated using(user_id=(select auth.uid()) and public.account_allowed()) with check(user_id=(select auth.uid()) and public.account_allowed() and cancel_requested=true);
grant update(is_read) on public.user_notifications to authenticated;
create policy read_notification on public.user_notifications for update to authenticated using(user_id=(select auth.uid()) and public.account_allowed()) with check(user_id=(select auth.uid()) and public.account_allowed());
-- No default AI model, fabricated prices, API calls, or automatic opt-in.
revoke all on all tables in schema private from public,anon,authenticated;
grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;
grant all on all sequences in schema private to service_role;
grant all on public.ai_policy,public.conversations,public.ai_requests,public.chat_messages,public.ai_usage,public.ai_memory,public.jarvis_proposals,public.prepared_materials,public.user_notifications,public.push_subscriptions to service_role;
commit;
