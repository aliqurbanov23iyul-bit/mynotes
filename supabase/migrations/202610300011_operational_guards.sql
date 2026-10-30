begin;
create index ai_requests_owner_conversation on public.ai_requests(user_id,conversation_id);
create index ai_requests_source on public.ai_requests(user_id,source_note_id);
create index proposals_owner_date on public.jarvis_proposals(user_id,created_at desc);
create index materials_owner_date on public.prepared_materials(user_id,created_at desc);
create index memory_owner_date on public.ai_memory(user_id,created_at desc);
create index subscriptions_owner on public.push_subscriptions(user_id);
create index billing_date on private.usage_totals(created_at);
create index jobs_ready on public.jarvis_jobs(scheduled_at) where status in ('scheduled','retry');
create index opted_notes on public.notes(user_id,updated_at) where ai_analysis_allowed;
-- Pin/category changes do not re-send unchanged private text to a paid provider.
drop trigger touch_updated on public.notes;
create function private.touch_note_content() returns trigger language plpgsql set search_path='' as $$begin
 if (new.title,new.content,new.ai_analysis_allowed) is distinct from (old.title,old.content,old.ai_analysis_allowed) then new.updated_at=now();else new.updated_at=old.updated_at;end if;return new;
end$$;
create trigger touch_updated before update on public.notes for each row execute function private.touch_note_content();
create function private.cancel_stale_note_jobs() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.updated_at is distinct from old.updated_at then update public.jarvis_jobs set status='cancelled',lease_token=null,last_error='SOURCE_CHANGED' where user_id=new.user_id and source_note_id=new.id and source_updated_at is distinct from new.updated_at and status in ('scheduled','retry','processing');end if;return new;
end$$;
create trigger cancel_stale_note_jobs after update on public.notes for each row execute function private.cancel_stale_note_jobs();
create function public.expire_push_leases() returns void language plpgsql security definer set search_path='' as $$declare changed integer;begin
 update public.user_notifications set push_status='failed' where push_status='sending' and push_claimed_at<now()-interval '3 minutes';get diagnostics changed=row_count;
 if changed>0 then insert into private.system_events(component,code) values('push','PUSH_DELIVERY_UNCERTAIN');end if;
end$$;
revoke all on function private.touch_note_content(),private.cancel_stale_note_jobs(),public.expire_push_leases() from public,anon,authenticated;
grant execute on function public.expire_push_leases() to service_role;
commit;
