begin;
alter table public.ai_usage add column input_rate numeric(12,6) not null default 0;
alter table public.ai_usage add column output_rate numeric(12,6) not null default 0;
create function private.user_allowed(uid uuid) returns boolean language sql stable set search_path='' as $$select exists(select 1 from public.profiles where id=uid) and not exists(select 1 from private.blocked_accounts where user_id=uid)$$;
create function public.runtime_config() returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_build_object('system',(select to_jsonb(r) from private.runtime_config r),'providers',(select jsonb_agg(p) from private.provider_config p)) $$;
create function public.runtime_public() returns jsonb language plpgsql security definer set search_path='' as $$begin if not public.account_allowed() then raise exception 'Access denied' using errcode='42501';end if;return jsonb_build_object('ai_enabled',(select ai_enabled from private.runtime_config),'providers',(select jsonb_agg(jsonb_build_object('provider',provider,'enabled',enabled,'model',model,'input_per_million',input_per_million,'output_per_million',output_per_million)) from private.provider_config));end$$;
create function public.server_rate(uid uuid,kind text,max_hits integer default 30) returns void language plpgsql security definer set search_path='' as $$declare n integer;begin if not private.user_allowed(uid) then raise exception 'Account unavailable' using errcode='42501';end if;insert into private.rate_buckets(user_id,bucket,window_at,hits) values(uid,kind,date_trunc('minute',now()),1) on conflict(user_id,bucket,window_at) do update set hits=rate_buckets.hits+1 returning hits into n;if n>max_hits then raise exception 'RATE_LIMIT' using errcode='P0001';end if;end$$;
create function public.reserve_ai(uid uuid,rid uuid,selected_provider text,purpose text) returns jsonb language plpgsql security definer set search_path='' as $$
declare conf private.runtime_config;model private.provider_config;policy public.ai_policy;amount numeric;daily numeric;monthly numeric;dn bigint;mn bigint;usage_id uuid;begin
 select * into conf from private.runtime_config for update;
 if not conf.ai_enabled or not private.user_allowed(uid) then raise exception 'AI_DISABLED';end if;
 select * into policy from public.ai_policy where user_id=uid for update;
 if not found or not policy.paid_consent then raise exception 'CONSENT_REQUIRED';end if;
 select * into model from private.provider_config where provider=selected_provider;
 if not found or not model.enabled or model.model='' or model.input_per_million is null or model.output_per_million is null or model.context_tokens<=0 or model.max_output_tokens<=0 then raise exception 'MODEL_NOT_CONFIGURED';end if;
 if not exists(select 1 from public.ai_requests where id=rid and user_id=uid and not cancel_requested and status='pending') then raise exception 'REQUEST_INVALID';end if;
 if purpose in ('analysis','prepare') and not exists(select 1 from public.ai_requests r join public.notes n on n.id=r.source_note_id and n.user_id=r.user_id join public.ai_preferences a on a.user_id=r.user_id where r.id=rid and r.user_id=uid and n.ai_analysis_allowed and a.autopilot_enabled and a.notes_access_enabled and (not exists(select 1 from public.jarvis_jobs where id=rid) or exists(select 1 from public.jarvis_jobs j where j.id=rid and j.status='processing' and j.source_updated_at=n.updated_at))) then raise exception 'PERMISSION_REQUIRED';end if;
 -- Worst configured full-context + max output reservation, not an invented provider quota.
 amount=ceil((model.context_tokens*model.input_per_million+model.max_output_tokens*model.output_per_million)/1000000*100000000)/100000000;
 select coalesce(sum(case when created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC' then coalesce(cost_usd,reserved_usd) else 0 end),0),coalesce(sum(coalesce(cost_usd,reserved_usd)),0),count(*) filter(where created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),count(*) into daily,monthly,dn,mn from public.ai_usage where user_id=uid and created_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
 if daily+amount>policy.daily_usd or monthly+amount>policy.monthly_usd or dn>=policy.daily_requests or mn>=policy.monthly_requests then raise exception 'BUDGET_LIMIT';end if;
 select coalesce(sum(case when created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC' then coalesce(cost_usd,reserved_usd) else 0 end),0),coalesce(sum(coalesce(cost_usd,reserved_usd)),0) into daily,monthly from private.usage_totals where created_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
 if daily+amount>conf.global_daily_usd or monthly+amount>conf.global_monthly_usd then raise exception 'SYSTEM_BUDGET_LIMIT';end if;
 insert into public.ai_usage(user_id,request_id,provider,model,kind,reserved_usd,input_rate,output_rate) values(uid,rid,model.provider,model.model,purpose,amount,model.input_per_million,model.output_per_million) returning id into usage_id;
 insert into private.usage_totals(id,provider,reserved_usd) values(usage_id,model.provider,amount);
 return jsonb_build_object('id',usage_id,'reserved_usd',amount);
end$$;
create function public.settle_ai(usage_id uuid,p_input bigint,p_output bigint,result_status text) returns void language plpgsql security definer set search_path='' as $$declare entry public.ai_usage;begin
 if result_status not in ('completed','uncertain','failed') or p_input<0 or p_output<0 then raise exception 'Invalid settlement';end if;
 update public.ai_usage set input_tokens=p_input,output_tokens=p_output,status=result_status,cost_usd=case when result_status='completed' and p_input is not null and p_output is not null then ceil((p_input*input_rate+p_output*output_rate)/1000000*100000000)/100000000 else reserved_usd end,finished_at=now() where id=usage_id and status='reserved' returning * into entry;
 if found then update private.usage_totals set input_tokens=entry.input_tokens,output_tokens=entry.output_tokens,cost_usd=entry.cost_usd,status=entry.status where id=usage_id;end if;
end$$;
create function public.runtime_service(operation text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare value jsonb;rid uuid;uid uuid;begin
 if operation='request' then
 uid=(args->>'user_id')::uuid;rid=(args->>'id')::uuid;
 if not private.user_allowed(uid) then raise exception 'Account unavailable';end if;
 if args->>'lease_token' is not null and not exists(select 1 from public.jarvis_jobs where id=rid and user_id=uid and status='processing' and lease_token=(args->>'lease_token')::uuid) then raise exception 'DUPLICATE_REQUEST';end if;
 if args->>'source_note_id' is not null and not exists(select 1 from public.notes n join public.ai_preferences a on a.user_id=n.user_id where n.id=(args->>'source_note_id')::uuid and n.user_id=uid and n.ai_analysis_allowed and a.autopilot_enabled and a.notes_access_enabled) then raise exception 'PERMISSION_REQUIRED';end if;
 if args->>'conversation_id' is not null and not exists(select 1 from public.conversations where id=(args->>'conversation_id')::uuid and user_id=uid) then raise exception 'Conversation unavailable';end if;
 if exists(select 1 from public.ai_requests where id=rid) then
 if not exists(select 1 from public.jarvis_jobs where id=rid and user_id=uid and status='processing' and lease_token=(args->>'lease_token')::uuid) or exists(select 1 from public.ai_usage where request_id=rid) then raise exception 'DUPLICATE_REQUEST';end if;
 update public.ai_requests set status='pending',cancel_requested=false where id=rid and user_id=uid;
 else insert into public.ai_requests(id,user_id,conversation_id,source_note_id) values(rid,uid,(args->>'conversation_id')::uuid,(args->>'source_note_id')::uuid);end if;return jsonb_build_object('id',rid);
 elsif operation='cache_get' then select c.value into value from private.external_cache c where c.cache_key=args->>'key' and expires_at>now();return value;
 elsif operation='cache_set' then insert into private.external_cache(cache_key,value,expires_at) values(args->>'key',args->'value',now()+interval '30 minutes') on conflict(cache_key) do update set value=excluded.value,expires_at=excluded.expires_at;return '{}'::jsonb;
 elsif operation='event' then insert into private.system_events(component,code) values(left(args->>'component',40),left(args->>'code',80));return '{}'::jsonb;
 else raise exception 'Unknown service operation';end if;
end$$;
create function public.confirm_jarvis(proposal_id uuid,run_at timestamptz) returns uuid language plpgsql security definer set search_path='' as $$declare p public.jarvis_proposals;jid uuid;begin
 if not public.account_allowed() then raise exception 'Access denied' using errcode='42501';end if;
 select * into p from public.jarvis_proposals where id=proposal_id and user_id=auth.uid() for update;
 if not found or p.confirmed then raise exception 'Proposal unavailable';end if;
 if run_at<=now() or run_at>now()+interval '1 year' then raise exception 'Invalid schedule';end if;
 if not exists(select 1 from public.ai_preferences where user_id=auth.uid() and autopilot_enabled and notes_access_enabled) or not exists(select 1 from public.notes where id=p.note_id and user_id=auth.uid() and ai_analysis_allowed and updated_at=p.source_updated_at) then raise exception 'Permission or note changed';end if;
 insert into public.jarvis_jobs(user_id,source_note_id,source_updated_at,job_type,scheduled_at,status) values(auth.uid(),p.note_id,p.source_updated_at,'prepare_material',run_at,'scheduled') returning id into jid;
 update public.jarvis_proposals set confirmed=true where id=p.id;return jid;
end$$;
create function public.claim_jarvis() returns setof public.jarvis_jobs language plpgsql security definer set search_path='' as $$begin
 if not (select automation_enabled from private.runtime_config) then return;end if;
 update public.jarvis_jobs j set status='cancelled',last_error='SOURCE_OR_PERMISSION_CHANGED',lease_token=null where status in ('scheduled','retry') and (not private.user_allowed(j.user_id) or not exists(select 1 from public.ai_preferences a where a.user_id=j.user_id and a.autopilot_enabled and a.notes_access_enabled) or not exists(select 1 from public.notes n where n.id=j.source_note_id and n.user_id=j.user_id and n.ai_analysis_allowed and n.updated_at=j.source_updated_at));
 -- Expired leases are never blindly replayed after a provider may have billed.
 update public.jarvis_jobs j set status=case when attempts>=3 or exists(select 1 from public.ai_usage u where u.request_id=j.id) then 'failed' else 'retry' end,last_error='LEASE_EXPIRED_REVIEW',lease_token=null where status='processing' and lease_until<now();
 return query with candidate as(select j.id from public.jarvis_jobs j join public.ai_preferences a on a.user_id=j.user_id join public.notes n on n.id=j.source_note_id and n.user_id=j.user_id where j.status in ('scheduled','retry') and j.scheduled_at<=now() and j.attempts<3 and a.autopilot_enabled and a.notes_access_enabled and n.ai_analysis_allowed and n.updated_at=j.source_updated_at and private.user_allowed(j.user_id) order by j.scheduled_at for update of j skip locked limit 1)
 update public.jarvis_jobs j set status='processing',attempts=attempts+1,lease_until=now()+interval '3 minutes',lease_token=gen_random_uuid() from candidate c where j.id=c.id returning j.*;
end$$;
create function public.finish_jarvis(jid uuid,token uuid,material text,error_code text default null) returns boolean language plpgsql security definer set search_path='' as $$declare j public.jarvis_jobs;begin
 select * into j from public.jarvis_jobs where id=jid and status='processing' and lease_token=token for update;
 if not found then return false;end if;
 if error_code is not null then update public.jarvis_jobs set status='failed',last_error=left(error_code,80),lease_token=null where id=jid;return false;end if;
 if not (select automation_enabled from private.runtime_config) or not private.user_allowed(j.user_id) or not exists(select 1 from public.ai_preferences where user_id=j.user_id and autopilot_enabled and notes_access_enabled) or not exists(select 1 from public.notes where id=j.source_note_id and user_id=j.user_id and ai_analysis_allowed and updated_at=j.source_updated_at) then update public.jarvis_jobs set status='cancelled',lease_token=null where id=jid;return false;end if;
 if material is null or char_length(material)>120000 then raise exception 'Invalid material';end if;
 insert into public.prepared_materials(user_id,job_id,title,content) values(j.user_id,jid,'Hazırlıq materialı',material) on conflict(job_id) do nothing;
 insert into public.user_notifications(user_id,kind,title,body,dedupe_key) select j.user_id,'jarvis','Hazırlıq materialın hazırdır','JARVIS bölməsindən materialı aça bilərsən.','job:'||jid where exists(select 1 from public.ai_policy where user_id=j.user_id and notification_consent) on conflict(user_id,dedupe_key) do nothing;
 update public.jarvis_jobs set status='completed',lease_token=null,last_error=null where id=jid;return true;
end$$;
-- Stop/cancel revokes leases too; no content is published after permission revocation.
create function private.revoke_jarvis() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not new.autopilot_enabled or not new.notes_access_enabled then update public.jarvis_jobs set status='cancelled',lease_token=null where user_id=new.user_id and status in ('scheduled','retry','processing');end if;return new;end$$;
create trigger revoke_jarvis after update on public.ai_preferences for each row execute function private.revoke_jarvis();
revoke all on function public.runtime_config(),public.server_rate(uuid,text,integer),public.reserve_ai(uuid,uuid,text,text),public.settle_ai(uuid,bigint,bigint,text),public.runtime_service(text,jsonb),public.claim_jarvis(),public.finish_jarvis(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.runtime_config(),public.server_rate(uuid,text,integer),public.reserve_ai(uuid,uuid,text,text),public.settle_ai(uuid,bigint,bigint,text),public.runtime_service(text,jsonb),public.claim_jarvis(),public.finish_jarvis(uuid,uuid,text,text) to service_role;
revoke all on function public.runtime_public(),public.confirm_jarvis(uuid,timestamptz) from public,anon;
grant execute on function public.runtime_public(),public.confirm_jarvis(uuid,timestamptz) to authenticated;
revoke all on function private.user_allowed(uuid),private.revoke_jarvis() from public,anon,authenticated;
commit;
