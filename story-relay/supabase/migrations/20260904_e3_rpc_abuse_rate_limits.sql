-- Story Relay Phase E3: lightweight per-user abuse rate limits for high-cost RPCs.
-- Scope: current ~100-person classroom product. Limits are intentionally loose and
-- keyed by authenticated user so a legitimate classroom burst does not share one bucket.

begin;

create table if not exists public.rpc_rate_limit_state (
  user_id uuid not null,
  action text not null,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, action)
);

alter table public.rpc_rate_limit_state enable row level security;
revoke all on table public.rpc_rate_limit_state from public, anon, authenticated;

create or replace function public.consume_rpc_rate_limit(
  p_action text,
  p_max_requests integer,
  p_window_seconds integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if nullif(trim(p_action), '') is null then
    raise exception 'Rate-limit action is required';
  end if;
  if p_max_requests <= 0 or p_window_seconds <= 0 then
    raise exception 'Invalid rate-limit configuration';
  end if;

  insert into public.rpc_rate_limit_state (
    user_id, action, window_started_at, request_count, updated_at
  ) values (
    v_user_id, p_action, v_now, 1, v_now
  )
  on conflict (user_id, action) do update
  set window_started_at = case
        when public.rpc_rate_limit_state.window_started_at <= v_now - make_interval(secs => p_window_seconds)
          then v_now
        else public.rpc_rate_limit_state.window_started_at
      end,
      request_count = case
        when public.rpc_rate_limit_state.window_started_at <= v_now - make_interval(secs => p_window_seconds)
          then 1
        else public.rpc_rate_limit_state.request_count + 1
      end,
      updated_at = v_now
  returning request_count into v_count;

  if v_count > p_max_requests then
    raise exception 'Too many requests for %. Please wait and try again.', p_action
      using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.consume_rpc_rate_limit(text,integer,integer) from public, anon, authenticated;

-- Preserve the already-tested implementations as internal functions. The public
-- RPC names below become thin SECURITY DEFINER wrappers that rate-limit first.
do $$
begin
  if to_regprocedure('public.join_activity_by_code_unthrottled(text)') is null then
    alter function public.join_activity_by_code(text) rename to join_activity_by_code_unthrottled;
  end if;
  if to_regprocedure('public.start_relay_round_unthrottled(uuid)') is null then
    alter function public.start_relay_round(uuid) rename to start_relay_round_unthrottled;
  end if;
  if to_regprocedure('public.submit_segment_unthrottled(uuid,text)') is null then
    alter function public.submit_segment(uuid,text) rename to submit_segment_unthrottled;
  end if;
  if to_regprocedure('public.nominate_candidate_unthrottled(uuid,uuid)') is null then
    alter function public.nominate_candidate(uuid,uuid) rename to nominate_candidate_unthrottled;
  end if;
  if to_regprocedure('public.volunteer_for_round_unthrottled(uuid)') is null then
    alter function public.volunteer_for_round(uuid) rename to volunteer_for_round_unthrottled;
  end if;
end;
$$;

revoke all on function public.join_activity_by_code_unthrottled(text) from public, anon, authenticated;
revoke all on function public.start_relay_round_unthrottled(uuid) from public, anon, authenticated;
revoke all on function public.submit_segment_unthrottled(uuid,text) from public, anon, authenticated;
revoke all on function public.nominate_candidate_unthrottled(uuid,uuid) from public, anon, authenticated;
revoke all on function public.volunteer_for_round_unthrottled(uuid) from public, anon, authenticated;

create or replace function public.join_activity_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- One student normally joins once; 20/min still tolerates retries and mistakes.
  perform public.consume_rpc_rate_limit('join_activity_by_code', 20, 60);
  return public.join_activity_by_code_unthrottled(p_code);
end;
$$;
revoke all on function public.join_activity_by_code(text) from public, anon;
grant execute on function public.join_activity_by_code(text) to authenticated;

create or replace function public.start_relay_round(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Idempotent retries are allowed; rapid automated hammering is capped.
  perform public.consume_rpc_rate_limit('start_relay_round', 20, 60);
  return public.start_relay_round_unthrottled(p_group_id);
end;
$$;
revoke all on function public.start_relay_round(uuid) from public, anon;
grant execute on function public.start_relay_round(uuid) to authenticated;

create or replace function public.submit_segment(p_round_id uuid, p_content text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Eight successful submit attempts/minute is well above normal classroom pace.
  perform public.consume_rpc_rate_limit('submit_segment', 8, 60);
  return public.submit_segment_unthrottled(p_round_id, p_content);
end;
$$;
revoke all on function public.submit_segment(uuid,text) from public, anon;
grant execute on function public.submit_segment(uuid,text) to authenticated;

create or replace function public.nominate_candidate(p_round_id uuid, p_candidate_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A current writer may legitimately nominate many classmates in a large group.
  perform public.consume_rpc_rate_limit('nominate_candidate', 60, 60);
  perform public.nominate_candidate_unthrottled(p_round_id, p_candidate_id);
end;
$$;
revoke all on function public.nominate_candidate(uuid,uuid) from public, anon;
grant execute on function public.nominate_candidate(uuid,uuid) to authenticated;

create or replace function public.volunteer_for_round(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.consume_rpc_rate_limit('volunteer_for_round', 20, 60);
  perform public.volunteer_for_round_unthrottled(p_round_id);
end;
$$;
revoke all on function public.volunteer_for_round(uuid) from public, anon;
grant execute on function public.volunteer_for_round(uuid) to authenticated;

commit;
