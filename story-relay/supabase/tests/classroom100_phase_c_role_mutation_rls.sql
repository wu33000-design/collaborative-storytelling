-- CLASSROOM_100 Phase C: role/mutation boundary test
--
-- Verifies the remaining C1 authorization requirements:
--   1. Only an activity host can control that activity through host RPCs.
--   2. A platform administrator can inspect all retained activity content without
--      being a group member/current writer, but does not gain participant writes.
--   3. An ordinary participant cannot directly mutate writer_states,
--      relay_rounds, segments, or platform_admins.
--
-- Safety: all fixtures are created inside this transaction and rolled back.

begin;

do $$
declare
  v_host uuid;
  v_participant uuid;
  v_admin uuid;

  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_segment uuid := gen_random_uuid();
  v_round uuid := gen_random_uuid();

  v_rows integer;
  v_content jsonb;
  v_failed text := null;
  v_checks integer := 0;
  v_threw boolean;
begin
  -- Need one platform admin and one ordinary account. Prefer a non-admin host and
  -- a different non-admin participant when available; with only two accounts the
  -- same ordinary account may serve as host + participant.
  select pa.user_id
  into v_admin
  from public.platform_admins pa
  order by pa.created_at, pa.user_id
  limit 1;

  select p.id
  into v_host
  from public.profiles p
  where not exists (
    select 1 from public.platform_admins pa where pa.user_id = p.id
  )
  order by p.id
  limit 1;

  select p.id
  into v_participant
  from public.profiles p
  where not exists (
    select 1 from public.platform_admins pa where pa.user_id = p.id
  )
    and p.id <> v_host
  order by p.id
  limit 1;

  if v_admin is null or v_host is null then
    raise exception 'C1 role/mutation fixture requires at least one platform admin and one non-admin profile. No data was changed.';
  end if;

  if v_participant is null then
    v_participant := v_host;
  end if;

  -- SQL Editor owner creates a valid rollback-only fixture.
  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (
    v_activity,
    v_host,
    'C1M-' || upper(substr(replace(v_activity::text, '-', ''), 1, 6)),
    'CLASSROOM_100 C1 role/mutation rollback fixture',
    'active',
    null
  );

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'C1 Mutation Group');

  insert into public.stories (id, group_id, title, status)
  values (v_story, v_group, 'C1 Mutation Story', 'active');

  insert into public.group_members (group_id, user_id, role)
  values (v_group, v_participant, 'student');

  insert into public.writer_states (group_id, user_id, times_written, waiting_rounds, selection_weight)
  values (v_group, v_participant, 0, 0, 1)
  on conflict (group_id, user_id) do update
  set times_written = excluded.times_written,
      waiting_rounds = excluded.waiting_rounds,
      selection_weight = excluded.selection_weight;

  insert into public.segments (id, story_id, sequence_no, author_id, content, word_count)
  values (v_segment, v_story, 1, v_participant, 'C1 mutation fixture', 19);

  insert into public.relay_rounds (id, story_id, round_no, current_writer_id, status)
  values (v_round, v_story, 1, v_participant, 'writing');

  ---------------------------------------------------------------------------
  -- Host boundary: platform admin is intentionally NOT the fixture host.
  ---------------------------------------------------------------------------
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  v_threw := false;
  begin
    perform public.stop_activity(v_activity);
  exception when others then
    v_threw := true;
  end;
  v_checks := v_checks + 1;
  if not v_threw then
    v_failed := concat_ws('; ', v_failed, 'non_host stop_activity unexpectedly succeeded');
  end if;

  -- Owner positive control.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_host, 'role', 'authenticated')::text, true);

  v_threw := false;
  begin
    perform public.stop_activity(v_activity);
  exception when others then
    v_threw := true;
  end;
  v_checks := v_checks + 1;
  if v_threw then
    v_failed := concat_ws('; ', v_failed, 'host stop_activity failed');
  end if;

  -- Return fixture to active state as SQL Editor owner for remaining tests.
  perform set_config('role', 'none', true);
  update public.activities set status = 'active' where id = v_activity;
  update public.stories set status = 'active', completed_at = null where id = v_story;
  update public.relay_rounds set status = 'writing', completed_at = null where id = v_round;

  ---------------------------------------------------------------------------
  -- Ordinary participant direct-write boundary.
  ---------------------------------------------------------------------------
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_participant::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_participant, 'role', 'authenticated')::text, true);

  -- writer_states UPDATE must affect zero rows or raise.
  v_rows := 0;
  begin
    update public.writer_states
    set selection_weight = 999
    where group_id = v_group and user_id = v_participant;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly updated writer_states rows=' || v_rows);
  end if;

  -- writer_states DELETE must affect zero rows or raise.
  v_rows := 0;
  begin
    delete from public.writer_states
    where group_id = v_group and user_id = v_participant;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly deleted writer_states rows=' || v_rows);
  end if;

  -- relay_rounds INSERT must raise. Use a fully valid unique row so constraints
  -- cannot be the intended blocker.
  v_threw := false;
  begin
    insert into public.relay_rounds (id, story_id, round_no, current_writer_id, status)
    values (gen_random_uuid(), v_story, 99, v_participant, 'writing');
  exception when others then
    v_threw := true;
  end;
  v_checks := v_checks + 1;
  if not v_threw then
    v_failed := concat_ws('; ', v_failed, 'participant directly inserted relay_rounds');
  end if;

  v_rows := 0;
  begin
    update public.relay_rounds set round_no = 98 where id = v_round;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly updated relay_rounds rows=' || v_rows);
  end if;

  v_rows := 0;
  begin
    delete from public.relay_rounds where id = v_round;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly deleted relay_rounds rows=' || v_rows);
  end if;

  -- segments INSERT/UPDATE/DELETE must not succeed directly.
  v_threw := false;
  begin
    insert into public.segments (id, story_id, sequence_no, author_id, content, word_count)
    values (gen_random_uuid(), v_story, 99, v_participant, 'direct insert must fail', 23);
  exception when others then
    v_threw := true;
  end;
  v_checks := v_checks + 1;
  if not v_threw then
    v_failed := concat_ws('; ', v_failed, 'participant directly inserted segments');
  end if;

  v_rows := 0;
  begin
    update public.segments set content = 'direct update must fail' where id = v_segment;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly updated segments rows=' || v_rows);
  end if;

  v_rows := 0;
  begin
    delete from public.segments where id = v_segment;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly deleted segments rows=' || v_rows);
  end if;

  -- platform_admins INSERT/UPDATE/DELETE must be unavailable directly to an
  -- ordinary participant.
  v_threw := false;
  begin
    insert into public.platform_admins (user_id) values (v_participant);
  exception when others then
    v_threw := true;
  end;
  v_checks := v_checks + 1;
  if not v_threw then
    v_failed := concat_ws('; ', v_failed, 'participant directly inserted platform_admins');
  end if;

  v_rows := 0;
  begin
    update public.platform_admins set user_id = user_id where user_id = v_admin;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly updated platform_admins rows=' || v_rows);
  end if;

  v_rows := 0;
  begin
    delete from public.platform_admins where user_id = v_admin;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'participant directly deleted platform_admins rows=' || v_rows);
  end if;

  ---------------------------------------------------------------------------
  -- Platform admin read-only inspection without membership/current-writer role.
  ---------------------------------------------------------------------------
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  select public.get_platform_activity_content(v_activity) into v_content;
  v_checks := v_checks + 1;
  if v_content is null
     or jsonb_array_length(coalesce(v_content->'groups', '[]'::jsonb)) <> 1
     or jsonb_array_length(coalesce(v_content->'stories', '[]'::jsonb)) <> 1
     or jsonb_array_length(coalesce(v_content->'segments', '[]'::jsonb)) <> 1
     or jsonb_array_length(coalesce(v_content->'rounds', '[]'::jsonb)) <> 1 then
    v_failed := concat_ws('; ', v_failed, 'platform_admin content inspection did not return complete fixture');
  end if;

  -- Explicitly verify the admin is not a member of the fixture group.
  perform set_config('role', 'none', true);
  select count(*) into v_rows
  from public.group_members
  where group_id = v_group and user_id = v_admin and left_at is null;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'platform_admin unexpectedly fixture member');
  end if;

  -- Admin still must not gain direct participant content mutation merely from
  -- platform-admin status.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  v_rows := 0;
  begin
    update public.segments set content = 'admin direct edit must fail' where id = v_segment;
    get diagnostics v_rows = row_count;
  exception when others then
    v_rows := 0;
  end;
  v_checks := v_checks + 1;
  if v_rows <> 0 then
    v_failed := concat_ws('; ', v_failed, 'platform_admin directly updated segment rows=' || v_rows);
  end if;

  -- Restore SQL Editor role before reporting.
  perform set_config('role', 'none', true);

  if v_failed is not null then
    raise exception 'CLASSROOM_100 C1 role/mutation RLS failed: %', v_failed;
  end if;

  raise notice 'CLASSROOM_100 C1 role/mutation RLS passed | checks=% | fixture will be rolled back', v_checks;
end;
$$;

rollback;

select 'CLASSROOM_100 C1 role/mutation RLS passed' as result;
