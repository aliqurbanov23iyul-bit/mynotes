begin;
create table private.blocked_accounts(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
revoke all on private.blocked_accounts from public,anon,authenticated;
create function public.account_allowed() returns boolean language sql stable security definer set search_path='' as $$ select (select auth.uid()) is not null and exists(select 1 from public.profiles where id=(select auth.uid())) and not exists(select 1 from private.blocked_accounts where user_id=(select auth.uid())) $$;
-- Avoid RLS recursion in account_allowed(): owner security definer bypasses profiles RLS.
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select public.account_allowed() and exists(select 1 from private.admin_members where user_id=(select auth.uid()))$$;
do $$declare t text;begin foreach t in array array['profiles','notes','tasks','calendar_events','favorite_movies','ai_preferences','jarvis_jobs','app_settings'] loop execute format('create policy account_enabled on public.%I as restrictive for all to authenticated using((select public.account_allowed())) with check((select public.account_allowed()))',t);end loop;end$$;
-- Guard all workspace RPCs, including SECURITY DEFINER code paths.
alter function public.load_workspace() rename to load_workspace_internal;
alter function public.save_workspace(bigint,jsonb) rename to save_workspace_internal;
alter function public.import_legacy_notes(jsonb) rename to import_legacy_notes_internal;
-- Internal implementation lives in private schema, inaccessible through PostgREST.
alter function public.load_workspace_internal() set schema private;
alter function public.save_workspace_internal(bigint,jsonb) set schema private;
alter function public.import_legacy_notes_internal(jsonb) set schema private;
revoke all on function private.load_workspace_internal(),private.save_workspace_internal(bigint,jsonb),private.import_legacy_notes_internal(jsonb) from public,anon,authenticated;
create function public.load_workspace() returns jsonb language plpgsql security definer set search_path='' as $$begin if not public.account_allowed() then raise exception 'Account unavailable' using errcode='42501';end if;return private.load_workspace_internal();end$$;
create function public.save_workspace(expected_version bigint,payload jsonb) returns bigint language plpgsql security definer set search_path='' as $$begin if not public.account_allowed() then raise exception 'Account unavailable' using errcode='42501';end if;return private.save_workspace_internal(expected_version,payload);end$$;
create function public.import_legacy_notes(items jsonb) returns integer language plpgsql security definer set search_path='' as $$begin if not public.account_allowed() then raise exception 'Account unavailable' using errcode='42501';end if;return private.import_legacy_notes_internal(items);end$$;
create function public.admin_api(operation text,args jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;target uuid;key text;val jsonb;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if operation='stats' then
 select jsonb_build_object('users',(select count(*) from auth.users),'signed_in_7d',(select count(*) from auth.users where last_sign_in_at>=now()-interval '7 days'),'notes',(select count(*) from public.notes),'tasks',(select count(*) from public.tasks),'jobs',coalesce((select jsonb_object_agg(status,n) from(select status,count(*) n from public.jarvis_jobs group by status)x),'{}'::jsonb)) into result;
 elsif operation='users' then
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into result from(select u.id,u.email,p.display_name,u.created_at,u.last_sign_in_at,exists(select 1 from private.blocked_accounts b where b.user_id=u.id) blocked,exists(select 1 from private.admin_members a where a.user_id=u.id) is_admin from auth.users u left join public.profiles p on p.id=u.id where coalesce(u.email,'') ilike '%'||left(coalesce(args->>'search',''),100)||'%' or coalesce(p.display_name,'') ilike '%'||left(coalesce(args->>'search',''),100)||'%' order by u.created_at desc limit 50 offset greatest(0,least(coalesce((args->>'offset')::integer,0),100000)))x;
 elsif operation='access' then
 target=(args->>'user_id')::uuid;
 if target=auth.uid() or exists(select 1 from private.admin_members where user_id=target) then raise exception 'Admin accounts cannot be blocked here';end if;
 if not exists(select 1 from auth.users where id=target) then raise exception 'User not found';end if;
 if (args->>'blocked')::boolean then insert into private.blocked_accounts(user_id) values(target) on conflict do nothing;else delete from private.blocked_accounts where user_id=target;end if;
 insert into private.admin_audit(actor_id,action,target_id) values(auth.uid(),'access:'||coalesce(args->>'blocked',''),target);result='{"ok":true}';
 elsif operation='jobs' then
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into result from(select id,user_id,job_type,scheduled_at,status,created_at from public.jarvis_jobs order by scheduled_at desc limit 100 offset greatest(0,least(coalesce((args->>'offset')::integer,0),100000)))x;
 elsif operation='cancel_job' then
 target=(args->>'id')::uuid;update public.jarvis_jobs set status='cancelled' where id=target and status in ('draft','scheduled');
 if not found then raise exception 'Job not cancellable';end if;
 insert into private.admin_audit(actor_id,action,target_id) values(auth.uid(),'cancel_job',target);result='{"ok":true}';
 elsif operation='settings' then select jsonb_object_agg(setting_key,setting_value) into result from public.app_settings;
 elsif operation='setting' then
 key=args->>'key';val=args->'value';
 if key='featured_movie' then
 if jsonb_typeof(val) is distinct from 'string' or val#>>'{}' not in ('interstellar','dune','soul','arrival','grand','inception') then raise exception 'Invalid movie';end if;
 elsif key='features' then
 if jsonb_typeof(val) is distinct from 'object' or not(val ?& array['notes','calendar','jarvis']) or val-array['notes','calendar','jarvis']<>'{}'::jsonb or jsonb_typeof(val->'notes') is distinct from 'boolean' or jsonb_typeof(val->'calendar') is distinct from 'boolean' or jsonb_typeof(val->'jarvis') is distinct from 'boolean' then raise exception 'Invalid features';end if;
 elsif key='ai_models' then
 if jsonb_typeof(val) is distinct from 'object' or not(val ?& array['Gemini','Claude','Grok']) or val-array['Gemini','Claude','Grok']<>'{}'::jsonb then raise exception 'Invalid models';end if;
 foreach key in array array['Gemini','Claude','Grok'] loop
 if jsonb_typeof(val->key) is distinct from 'object' or jsonb_typeof(val#>array[key,'style']) is distinct from 'string' or jsonb_typeof(val#>array[key,'limit']) is distinct from 'number' or (val->key)-array['style','limit']<>'{}'::jsonb or not((val->key)?&array['style','limit']) or val#>>array[key,'style'] not in ('Balanslı','Qısa','Ətraflı') or (val#>>array[key,'limit'])::integer not between 1 and 10000 then raise exception 'Invalid model config';end if;
 end loop;key='ai_models';
 else raise exception 'Setting not permitted';end if;
 if val is null then raise exception 'Missing value';end if;
 update public.app_settings set setting_value=val where setting_key=key;
 insert into private.admin_audit(actor_id,action) values(auth.uid(),'setting:'||key);result='{"ok":true}';
 else raise exception 'Unknown admin operation';end if;
 return result;
end$$;
revoke all on function public.account_allowed(),public.load_workspace(),public.save_workspace(bigint,jsonb),public.import_legacy_notes(jsonb),public.admin_api(text,jsonb) from public,anon;
grant execute on function public.account_allowed(),public.load_workspace(),public.save_workspace(bigint,jsonb),public.import_legacy_notes(jsonb),public.admin_api(text,jsonb) to authenticated;
commit;
