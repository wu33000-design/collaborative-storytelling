-- CLASSROOM_100 D4: verify relay_rounds.started_at is populated by the database default.
-- Rollback-only. No test data remains.

begin;

do $$
declare
  v_story_id uuid;
  v_writer_id uuid;
  v_round_id uuid;
  v_started_at timestamptz;
begin
  select s.id, gm.user_id
  into v_story_id, v_writer_id
  from public.stories s
  join public.groups g on g.id = s.group_id
  join public.group_members gm on gm.group_id = g.id
  where gm.left_at is null
  order by s.id, gm.joined_at
  limit 1;

  if v_story_id is null or v_writer_id is null then
    raise exception 'D4 started_at fixture requires at least one story with one active group member';
  end if;

  insert into public.relay_rounds (story_id, round_no, current_writer_id, status)
  values (
    v_story_id,
    (select coalesce(max(rr.round_no), 0) + 100000 from public.relay_rounds rr where rr.story_id = v_story_id),
    v_writer_id,
    'writing'
  )
  returning id, started_at into v_round_id, v_started_at;

  if v_started_at is null then
    raise exception 'CLASSROOM_100 D4 round started_at failed: database default did not populate started_at';
  end if;

  if abs(extract(epoch from (clock_timestamp() - v_started_at))) > 10 then
    raise exception 'CLASSROOM_100 D4 round started_at failed: started_at is not close to current time';
  end if;
end $$;

rollback;

select 'CLASSROOM_100 D4 relay round started_at passed' as result;
