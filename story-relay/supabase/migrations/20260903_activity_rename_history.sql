-- Story Relay: activity renaming with participant-visible immutable history

begin;

create table if not exists public.activity_name_history (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  old_name text,
  new_name text,
  changed_by uuid not null references public.profiles(id),
  changed_at timestamptz not null default now()
);

create index if not exists activity_name_history_activity_changed_idx
  on public.activity_name_history(activity_id, changed_at desc);

alter table public.activity_name_history enable row level security;

drop policy if exists "activity name history visible to participants" on public.activity_name_history;
create policy "activity name history visible to participants"
on public.activity_name_history
for select
to authenticated
using (
  public.is_activity_teacher(activity_id)
  or exists (
    select 1
    from public.groups g
    join public.group_members gm on gm.group_id = g.id
    where g.activity_id = activity_name_history.activity_id
      and gm.user_id = auth.uid()
      and gm.left_at is null
  )
);

-- History is append-only from the client perspective. Only the RPC below writes it.
revoke insert, update, delete on public.activity_name_history from authenticated;

create or replace function public.rename_activity(
  p_activity_id uuid,
  p_new_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_old_name text;
  v_new_name text := nullif(trim(p_new_name), '');
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select name
  into v_old_name
  from public.activities
  where id = p_activity_id
    and teacher_id = v_user_id
  for update;

  if not found then
    raise exception 'Only the activity teacher can rename this activity';
  end if;

  if v_old_name is not distinct from v_new_name then
    return jsonb_build_object(
      'activity_id', p_activity_id,
      'old_name', v_old_name,
      'new_name', v_new_name,
      'changed', false
    );
  end if;

  update public.activities
  set name = v_new_name
  where id = p_activity_id;

  -- Story titles currently mirror the activity name, so keep them synchronized.
  update public.stories s
  set title = v_new_name
  from public.groups g
  where s.group_id = g.id
    and g.activity_id = p_activity_id;

  insert into public.activity_name_history (
    activity_id, old_name, new_name, changed_by
  ) values (
    p_activity_id, v_old_name, v_new_name, v_user_id
  );

  insert into public.activity_events (
    activity_id, type, actor_id, payload
  ) values (
    p_activity_id,
    'activity_renamed',
    v_user_id,
    jsonb_build_object('old_name', v_old_name, 'new_name', v_new_name)
  );

  return jsonb_build_object(
    'activity_id', p_activity_id,
    'old_name', v_old_name,
    'new_name', v_new_name,
    'changed', true
  );
end;
$$;

revoke all on function public.rename_activity(uuid,text) from public;
grant execute on function public.rename_activity(uuid,text) to authenticated;

commit;
