import { useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabase";

type Fixture = { activity_id: string; group_id: string; story_id: string };

type Stats = {
  status: string;
  expected: number;
  received: number;
  duplicates: number;
  maxHeartbeatDriftMs: number;
  durationMs: number | null;
};

const emptyStats: Stats = {
  status: "idle",
  expected: 200,
  received: 0,
  duplicates: 0,
  maxHeartbeatDriftMs: 0,
  durationMs: null,
};

export default function RealtimeCapacityProbe() {
  const [fixture, setFixture] = useState<Fixture | null>(null);
  const [subscribed, setSubscribed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState<Stats>(emptyStats);
  const seen = useRef(new Set<string>());
  const received = useRef(0);
  const duplicates = useRef(0);
  const maxDrift = useRef(0);
  const startedAt = useRef<number | null>(null);

  useEffect(() => {
    let expected = performance.now() + 100;
    const timer = window.setInterval(() => {
      const now = performance.now();
      const drift = Math.max(0, now - expected);
      maxDrift.current = Math.max(maxDrift.current, drift);
      expected = now + 100;
      setStats((current) => ({ ...current, maxHeartbeatDriftMs: Math.round(maxDrift.current) }));
    }, 100);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!fixture) return;

    setSubscribed(false);
    const onEvent = (payload: any) => {
      const row = payload.new ?? payload.old ?? {};
      const key = `${payload.table}:${payload.eventType}:${row.id ?? "no-id"}`;
      if (seen.current.has(key)) duplicates.current += 1;
      else seen.current.add(key);
      received.current += 1;

      if (received.current % 10 === 0 || received.current >= 200) {
        const duration = startedAt.current == null ? null : Math.round(performance.now() - startedAt.current);
        setStats((current) => ({
          ...current,
          received: received.current,
          duplicates: duplicates.current,
          durationMs: duration,
          status: received.current >= 200 ? "complete" : "receiving",
        }));
      }
    };

    const channel = supabase
      .channel(`classroom100-c2-capacity:${fixture.group_id}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "segments", filter: `story_id=eq.${fixture.story_id}` }, onEvent)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "relay_rounds", filter: `story_id=eq.${fixture.story_id}` }, onEvent)
      .subscribe((status) => setSubscribed(status === "SUBSCRIBED"));

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [fixture]);

  const createFixture = async () => {
    setBusy(true);
    setError(null);
    const { data, error: rpcError } = await supabase.rpc("create_classroom100_realtime_probe");
    setBusy(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    setFixture(data as Fixture);
  };

  const runBurst = async () => {
    if (!fixture) return;
    setBusy(true);
    setError(null);
    seen.current = new Set();
    received.current = 0;
    duplicates.current = 0;
    maxDrift.current = 0;
    startedAt.current = performance.now();
    setStats({ ...emptyStats, status: "running" });

    const { error: rpcError } = await supabase.rpc("run_classroom100_realtime_probe_burst", {
      p_story_id: fixture.story_id,
    });
    setBusy(false);
    if (rpcError) setError(rpcError.message);
  };

  const cleanup = async () => {
    if (!fixture) return;
    setBusy(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc("cleanup_classroom100_realtime_probe", {
      p_group_id: fixture.group_id,
    });
    setBusy(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    setFixture(null);
    setStats(emptyStats);
    setSubscribed(false);
  };

  const passed = stats.received === stats.expected && stats.duplicates === 0 && stats.maxHeartbeatDriftMs < 1000;

  return (
    <div className="min-h-screen bg-[#F5F1E9] p-6 text-[#1F2E2A]">
      <main className="mx-auto max-w-3xl rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-8 shadow-sm">
        <div className="font-mono text-xs uppercase tracking-[0.16em] text-[#A06B59]">Temporary Test Page</div>
        <h1 className="mt-3 font-serif text-3xl font-semibold text-[#233B35]">CLASSROOM_100 C2 Realtime Capacity Probe</h1>
        <p className="mt-3 text-sm leading-6 text-[#68746B]">平台管理者專用。建立暫時 group/story，訂閱 100 個 segment + 100 個 relay_round INSERT，檢查重複事件與瀏覽器 heartbeat 卡頓。</p>

        {error && <div className="mt-5 rounded-xl bg-[#F7E5DF] p-4 font-mono text-xs text-[#8D4033]">{error}</div>}

        <div className="mt-6 grid gap-3 sm:grid-cols-3">
          <button className="rounded-xl bg-[#233B35] px-4 py-3 text-sm font-semibold text-white disabled:opacity-50" disabled={busy || !!fixture} onClick={() => void createFixture()}>1. 建立 fixture</button>
          <button className="rounded-xl bg-[#355447] px-4 py-3 text-sm font-semibold text-white disabled:opacity-50" disabled={busy || !fixture || !subscribed || stats.status === "running" || stats.status === "receiving" || stats.received > 0} onClick={() => void runBurst()}>2. 執行 200-event burst</button>
          <button className="rounded-xl border border-[#B9B1A4] px-4 py-3 text-sm font-semibold disabled:opacity-50" disabled={busy || !fixture} onClick={() => void cleanup()}>3. 清理 fixture</button>
        </div>

        <div className="mt-7 grid gap-3 sm:grid-cols-2">
          <Stat label="Realtime" value={subscribed ? "SUBSCRIBED" : fixture ? "CONNECTING" : "NOT STARTED"} />
          <Stat label="Status" value={stats.status} />
          <Stat label="Events" value={`${stats.received} / ${stats.expected}`} />
          <Stat label="Duplicates" value={String(stats.duplicates)} />
          <Stat label="Max heartbeat drift" value={`${stats.maxHeartbeatDriftMs} ms`} />
          <Stat label="Receive duration" value={stats.durationMs == null ? "—" : `${stats.durationMs} ms`} />
        </div>

        {stats.received >= stats.expected && (
          <div className={`mt-6 rounded-2xl p-5 font-semibold ${passed ? "bg-[#E7EFE5] text-[#355447]" : "bg-[#F7E5DF] text-[#8D4033]"}`}>
            {passed ? "PASS：200 events 全收、0 duplicate、無 >1s 明顯主執行緒卡頓。" : "FAIL：事件數、duplicate 或 heartbeat drift 未達門檻。"}
          </div>
        )}

        {fixture && <div className="mt-5 break-all font-mono text-[11px] text-[#7B756D]">group={fixture.group_id}<br />story={fixture.story_id}</div>}
      </main>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl bg-[#F3EEE5] p-4"><div className="text-xs text-[#7B756D]">{label}</div><div className="mt-1 font-mono text-sm font-semibold text-[#233B35]">{value}</div></div>;
}
