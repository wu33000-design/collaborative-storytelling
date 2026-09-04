-- Story Relay: reserve finite multi-group activities for platform administrators.
--
-- Product rule:
--   - Normal hosts still use the existing groups schema internally, but their
--     activities must keep group_size = NULL, which means one unlimited group.
--   - Platform administrators may set a finite group_size and therefore use
--     automatic multi-group allocation.
--
-- This does not rewrite or delete existing activities. Existing finite
-- group_size values remain valid until someone attempts to change them.

begin;

create or replace function public.enforce_platform_admin_advanced_grouping()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if new.group_size is null then
    return new;
  end if;

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = v_user_id
  ) then
    raise exception 'Advanced grouping is available only to platform administrators';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_platform_admin_advanced_grouping() from public;

DROP TRIGGER IF EXISTS activities_platform_admin_advanced_grouping
  ON public.activities;

create trigger activities_platform_admin_advanced_grouping
before insert or update of group_size on public.activities
for each row
execute function public.enforce_platform_admin_advanced_grouping();

commit;
