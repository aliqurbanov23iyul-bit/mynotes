begin;
alter table public.jarvis_jobs drop constraint jarvis_jobs_job_type_check;
alter table public.jarvis_jobs add constraint jarvis_jobs_job_type_check check(job_type in ('prepare_material','review_plan','analyze_note'));
alter table public.jarvis_proposals add column job_id uuid unique references public.jarvis_jobs(id) on delete cascade;
create function public.enqueue_analysis() returns integer language plpgsql security definer set search_path='' as $$declare n integer;begin
 if not (select automation_enabled from private.runtime_config) then return 0;end if;
 insert into public.jarvis_jobs(user_id,source_note_id,source_updated_at,job_type,scheduled_at,status)
 select n.user_id,n.id,n.updated_at,'analyze_note',n.updated_at,'scheduled' from public.notes n join public.ai_preferences a on a.user_id=n.user_id join public.ai_policy p on p.user_id=n.user_id where n.ai_analysis_allowed and a.autopilot_enabled and a.notes_access_enabled and p.paid_consent and private.user_allowed(n.user_id) and not exists(select 1 from public.jarvis_proposals q where q.user_id=n.user_id and q.note_id=n.id and q.source_updated_at=n.updated_at) and not exists(select 1 from public.jarvis_jobs j where j.user_id=n.user_id and j.source_note_id=n.id and j.source_updated_at=n.updated_at and j.job_type='analyze_note') on conflict do nothing;
 get diagnostics n=row_count;return n;
end$$;
create function public.finish_analysis(jid uuid,token uuid,summary text,suggested_time text,uncertainty text) returns boolean language plpgsql security definer set search_path='' as $$declare j public.jarvis_jobs;begin
 select * into j from public.jarvis_jobs where id=jid and status='processing' and job_type='analyze_note' and lease_token=token for update;
 if not found then return false;end if;
 if not (select automation_enabled from private.runtime_config) or not private.user_allowed(j.user_id) or not exists(select 1 from public.ai_preferences where user_id=j.user_id and autopilot_enabled and notes_access_enabled) or not exists(select 1 from public.notes where id=j.source_note_id and user_id=j.user_id and ai_analysis_allowed and updated_at=j.source_updated_at) then update public.jarvis_jobs set status='cancelled',lease_token=null where id=jid;return false;end if;
 if summary is null or char_length(summary)>3000 or uncertainty is null or char_length(uncertainty)>3000 then raise exception 'Invalid analysis';end if;
 insert into public.jarvis_proposals(user_id,note_id,source_updated_at,summary,suggested_time,uncertainty,job_id) values(j.user_id,j.source_note_id,j.source_updated_at,summary,left(suggested_time,100),uncertainty,j.id) on conflict(job_id) do nothing;
 insert into public.user_notifications(user_id,kind,title,body,dedupe_key) select j.user_id,'jarvis','Hazırlıq təklifi hazırdır','Tarix və vaxtı JARVIS fəaliyyətlərində təsdiqləyə bilərsən.','proposal:'||jid where exists(select 1 from public.ai_policy p join public.ai_preferences a on a.user_id=p.user_id where p.user_id=j.user_id and p.notification_consent and a.notifications_enabled) on conflict(user_id,dedupe_key) do nothing;
 update public.jarvis_jobs set status='completed',lease_token=null,last_error=null where id=jid;return true;
end$$;
revoke all on function public.enqueue_analysis(),public.finish_analysis(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.enqueue_analysis(),public.finish_analysis(uuid,uuid,text,text,text) to service_role;
commit;
