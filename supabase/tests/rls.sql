-- Run only on a disposable Supabase local/staging database, as postgres.
-- This transaction rolls back fixtures. Stop on any raised exception.
begin;
insert into auth.users(id,email,raw_user_meta_data) values
('91000000-0000-4000-8000-000000000001','rls-a@example.test','{}'),
('91000000-0000-4000-8000-000000000002','rls-b@example.test','{}');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into public.notes(id,user_id,title,content) values('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','RLS fixture','private');
reset role;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.notes where id='92000000-0000-4000-8000-000000000001') then raise exception 'FAIL cross-owner read';end if;
 update public.notes set title='evil' where id='92000000-0000-4000-8000-000000000001';
 if found then raise exception 'FAIL cross-owner update';end if;
 delete from public.notes where id='92000000-0000-4000-8000-000000000001';
 if found then raise exception 'FAIL cross-owner delete';end if;
 begin insert into public.notes(user_id,title,content) values('91000000-0000-4000-8000-000000000001','spoof','x');raise exception 'FAIL forged user_id';exception when insufficient_privilege then null;end;
 begin perform public.admin_api('stats');raise exception 'FAIL ordinary admin access';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$begin if not exists(select 1 from public.notes where title='RLS fixture') then raise exception 'FAIL owner read';end if;end$$;
reset role;
rollback;
