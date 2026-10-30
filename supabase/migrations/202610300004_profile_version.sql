begin;
create function private.profile_revision() returns trigger language plpgsql set search_path='' as $$begin if (new.display_name,new.avatar_url) is distinct from (old.display_name,old.avatar_url) then new.workspace_version=greatest(new.workspace_version,old.workspace_version+1);end if;return new;end$$;
create trigger profile_revision before update on public.profiles for each row execute function private.profile_revision();
revoke all on function private.profile_revision() from public,anon,authenticated;
commit;
