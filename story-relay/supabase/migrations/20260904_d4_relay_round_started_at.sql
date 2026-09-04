-- D4: every relay round needs a start timestamp so per-round limits can be enforced and displayed.

begin;

alter table public.relay_rounds
  alter column started_at set default now();

-- Repair only currently active rounds. Historical completed/expired rounds are left untouched
-- because their true start instant cannot be reconstructed reliably.
update public.relay_rounds
set started_at = now()
where status in ('open', 'writing')
  and started_at is null;

commit;
