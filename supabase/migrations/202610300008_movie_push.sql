begin;
alter table public.favorite_movies drop constraint favorite_movies_status_check;
alter table public.favorite_movies add constraint favorite_movies_status_check check(status in ('favorite','watchlist','watched','disliked'));
alter table public.user_notifications drop constraint user_notifications_push_status_check;
alter table public.user_notifications add constraint user_notifications_push_status_check check(push_status in ('pending','sending','sent','unsupported','failed'));
alter table public.user_notifications add column push_claimed_at timestamptz;
create function public.claim_push() returns setof public.user_notifications language sql security definer set search_path='' as $$
 with jobs as(select n.id from public.user_notifications n join public.ai_policy p on p.user_id=n.user_id join public.ai_preferences a on a.user_id=n.user_id where n.push_status='pending' and p.push_enabled and p.notification_consent and a.notifications_enabled and private.user_allowed(n.user_id) order by n.created_at for update of n skip locked limit 5)
 update public.user_notifications n set push_status='sending',push_claimed_at=now() from jobs where n.id=jobs.id returning n.*;
$$;
revoke all on function public.claim_push() from public,anon,authenticated;
grant execute on function public.claim_push() to service_role;
commit;
