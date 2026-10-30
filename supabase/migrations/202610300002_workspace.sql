begin;
create function public.load_workspace() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('profile',to_jsonb(p),'notes',coalesce((select jsonb_agg(n order by n.is_pinned desc,n.updated_at desc) from public.notes n where user_id=p.id),'[]'::jsonb),'tasks',coalesce((select jsonb_agg(t order by t.due_at) from public.tasks t where user_id=p.id),'[]'::jsonb),'events',coalesce((select jsonb_agg(e order by e.starts_at) from public.calendar_events e where user_id=p.id),'[]'::jsonb),'movies',coalesce((select jsonb_agg(m) from public.favorite_movies m where user_id=p.id),'[]'::jsonb),'preferences',(select to_jsonb(a) from public.ai_preferences a where user_id=p.id),'settings',(select jsonb_object_agg(setting_key,setting_value) from public.app_settings),'jobs',coalesce((select jsonb_agg(j order by j.scheduled_at desc) from public.jarvis_jobs j where user_id=p.id),'[]'::jsonb),'imported',exists(select 1 from private.imports i where i.user_id=p.id)) from public.profiles p where p.id=(select auth.uid());
$$;
create function private.bump_workspace() returns trigger language plpgsql security definer set search_path='' as $$begin update public.profiles set workspace_version=workspace_version+1 where id=coalesce(new.user_id,old.user_id);return coalesce(new,old);end$$;
do $$declare t text;begin foreach t in array array['notes','tasks','calendar_events','favorite_movies','ai_preferences'] loop execute format('create trigger workspace_changed after insert or update or delete on public.%I for each row execute function private.bump_workspace()',t);end loop;end$$;
-- Atomic UI commit with optimistic version control. All ownership is derived from auth.uid().
create function public.save_workspace(expected_version bigint,payload jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); current_version bigint; item jsonb; nid uuid;begin
 if uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 select workspace_version into current_version from public.profiles where id=uid for update;
 if not found then raise exception 'Profile missing' using errcode='42501';end if;
 if expected_version is null or current_version<>expected_version then raise exception 'WORKSPACE_CONFLICT' using errcode='40001';end if;
 if payload is null or jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>4000000 then raise exception 'Workspace too large';end if;
 if jsonb_typeof(payload->'notes') is distinct from 'array' or jsonb_typeof(payload->'tasks') is distinct from 'array' or jsonb_typeof(payload->'events') is distinct from 'array' or jsonb_typeof(payload->'movies') is distinct from 'array' or not(payload ?& array['notes','tasks','events','movies','preferences','name']) then raise exception 'Invalid workspace';end if;
 for item in select value from jsonb_array_elements(payload->'notes') loop
 nid=(item->>'id')::uuid;
 if exists(select 1 from public.notes where id=nid and user_id<>uid) then raise exception 'Ownership violation' using errcode='42501';end if;
 insert into public.notes(id,user_id,title,content,category,is_pinned) values(nid,uid,item->>'title',item->>'content',item->>'category',(item->>'is_pinned')::boolean)
 on conflict(id) do update set title=excluded.title,content=excluded.content,category=excluded.category,is_pinned=excluded.is_pinned where notes.user_id=uid and (notes.title,notes.content,notes.category,notes.is_pinned) is distinct from (excluded.title,excluded.content,excluded.category,excluded.is_pinned);
 end loop;
 delete from public.notes where user_id=uid and id not in(select (value->>'id')::uuid from jsonb_array_elements(payload->'notes'));
 for item in select value from jsonb_array_elements(payload->'tasks') loop
 nid=(item->>'id')::uuid;
 if exists(select 1 from public.tasks where id=nid and user_id<>uid) then raise exception 'Ownership violation' using errcode='42501';end if;
 insert into public.tasks(id,user_id,title,description,due_at,status,priority) values(nid,uid,item->>'title',coalesce(item->>'description',''),(item->>'due_at')::timestamptz,item->>'status',item->>'priority')
 on conflict(id) do update set title=excluded.title,description=excluded.description,due_at=excluded.due_at,status=excluded.status,priority=excluded.priority where tasks.user_id=uid and (tasks.title,tasks.description,tasks.due_at,tasks.status,tasks.priority) is distinct from (excluded.title,excluded.description,excluded.due_at,excluded.status,excluded.priority);
 end loop;
 delete from public.tasks where user_id=uid and id not in(select (value->>'id')::uuid from jsonb_array_elements(payload->'tasks'));
 for item in select value from jsonb_array_elements(payload->'events') loop
 nid=(item->>'id')::uuid;
 if exists(select 1 from public.calendar_events where id=nid and user_id<>uid) then raise exception 'Ownership violation' using errcode='42501';end if;
 insert into public.calendar_events(id,user_id,title,description,starts_at,ends_at) values(nid,uid,item->>'title',coalesce(item->>'description',''),(item->>'starts_at')::timestamptz,(item->>'ends_at')::timestamptz)
 on conflict(id) do update set title=excluded.title,description=excluded.description,starts_at=excluded.starts_at,ends_at=excluded.ends_at where calendar_events.user_id=uid and (calendar_events.title,calendar_events.description,calendar_events.starts_at,calendar_events.ends_at) is distinct from (excluded.title,excluded.description,excluded.starts_at,excluded.ends_at);
 end loop;
 delete from public.calendar_events where user_id=uid and id not in(select (value->>'id')::uuid from jsonb_array_elements(payload->'events'));
 delete from public.favorite_movies m where m.user_id=uid and not exists(select 1 from jsonb_array_elements(payload->'movies') i where i->>'status'=m.status and ((i->>'catalog_key') is not distinct from m.catalog_key) and ((i->>'tmdb_movie_id')::bigint is not distinct from m.tmdb_movie_id));
 for item in select value from jsonb_array_elements(payload->'movies') loop
 insert into public.favorite_movies(user_id,tmdb_movie_id,catalog_key,status) values(uid,(item->>'tmdb_movie_id')::bigint,item->>'catalog_key',item->>'status') on conflict do nothing;end loop;
 insert into public.ai_preferences(user_id,autopilot_enabled,notes_access_enabled,notifications_enabled) values(uid,coalesce((payload#>>'{preferences,autopilot_enabled}')::boolean,false),coalesce((payload#>>'{preferences,notes_access_enabled}')::boolean,false),coalesce((payload#>>'{preferences,notifications_enabled}')::boolean,true)) on conflict(user_id) do update set autopilot_enabled=excluded.autopilot_enabled,notes_access_enabled=excluded.notes_access_enabled,notifications_enabled=excluded.notifications_enabled;
 update public.profiles set display_name=payload->>'name',workspace_version=workspace_version+1 where id=uid returning workspace_version into current_version;
 return current_version;
end$$;
create function public.import_legacy_notes(items jsonb) returns integer language plpgsql security definer set search_path='' as $$declare uid uuid=auth.uid();item jsonb;n integer=0;begin
 if uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 perform 1 from public.profiles where id=uid for update;
 if exists(select 1 from private.imports where user_id=uid) then return 0;end if;
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items)>1000 or octet_length(items::text)>4000000 then raise exception 'Invalid import';end if;
 for item in select value from jsonb_array_elements(items) loop
 insert into public.notes(user_id,title,content,category,is_pinned,legacy_import_key) values(uid,item->>'title',item->>'body',item->>'category',coalesce((item->>'pinned')::boolean,false),coalesce(item->>'id',gen_random_uuid()::text));n=n+1;
 end loop;
 insert into private.imports(user_id) values(uid);return n;
end$$;
revoke all on function public.load_workspace(),public.save_workspace(bigint,jsonb),public.import_legacy_notes(jsonb) from public,anon;
grant execute on function public.load_workspace(),public.save_workspace(bigint,jsonb),public.import_legacy_notes(jsonb) to authenticated;
revoke all on function private.bump_workspace() from public,anon,authenticated;
commit;
