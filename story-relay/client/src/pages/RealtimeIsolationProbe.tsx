import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";

type ProbeEvent = {
  id: number;
  receivedAt: string;
  table: string;
  eventType: string;
  newRow: Record<string, unknown> | null;
  oldRow: Record<string, unknown> | null;
};

const TABLES = [
  "stories",
  "segments",
  "relay_rounds",
  "group_members",
  "nominations",
  "volunteers",
  "activity_events",
] as const;

export default function RealtimeIsolationProbe() {
  const [status, setStatus] = useState("CONNECTING");
  const [userLabel, setUserLabel] = useState("讀取中…");
  const [events, setEvents] = useState<ProbeEvent[]>([]);

  useEffect(() => {
    let nextId = 1;
    void supabase.auth.getSession().then(({ data }) => {
      const user = data.session?.user;
      setUserLabel(user ? `${user.email ?? "no-email"} · ${user.id}` : "未登入");
    });

    let channel = supabase.channel(`classroom100-realtime-probe:${crypto.randomUUID()}`);
    for (const table of TABLES) {
      channel = channel.on(
        "postgres_changes",
        { event: "*", schema: "public", table },
        (payload) => {
          setEvents((current) => [
            {
              id: nextId++,
              receivedAt: new Date().toISOString(),
              table,
              eventType: payload.eventType,
              newRow: (payload.new as Record<string, unknown>) ?? null,
              oldRow: (payload.old as Record<string, unknown>) ?? null,
            },
            ...current,
          ].slice(0, 200));
        },
      );
    }

    channel.subscribe((nextStatus) => setStatus(nextStatus));

    return () => {
      void supabase.removeChannel(channel);
    };
  }, []);

  const counts = useMemo(() => {
    const map = new Map<string, number>();
    for (const table of TABLES) map.set(table, 0);
    for (const event of events) map.set(event.table, (map.get(event.table) ?? 0) + 1);
    return map;
  }, [events]);

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A]">
      <main className="mx-auto max-w-6xl">
        <header className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm">
          <div className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">CLASSROOM_100 · C1</div>
          <h1 className="mt-3 font-serif text-4xl font-semibold text-[#233B35]">Realtime Isolation Probe</h1>
          <p className="mt-4 max-w-3xl text-sm leading-7 text-[#68746B]">
            這是未連結的安全測試頁。它刻意不加 row filter 訂閱 group-scoped Realtime tables，讓資料庫 RLS 自己決定目前登入者能收到哪些事件。
          </p>
          <div className="mt-5 grid gap-3 text-xs sm:grid-cols-2">
            <div className="rounded-xl bg-[#F3EEE5] p-4"><span className="font-semibold">登入者：</span>{userLabel}</div>
            <div className="rounded-xl bg-[#F3EEE5] p-4"><span className="font-semibold">Realtime：</span>{status}</div>
          </div>
        </header>

        <section className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-semibold text-[#233B35]">收到的事件</h2>
              <p className="mt-1 text-xs leading-5 text-[#68746B]">測試前先清空，再由另一組觸發操作。若此頁收到不屬於目前使用者小組的 payload，即視為失敗。</p>
            </div>
            <button type="button" onClick={() => setEvents([])} className="rounded-xl border border-[#CFC7BA] px-4 py-2 text-sm font-semibold text-[#355447] hover:bg-[#F3EEE5]">清空紀錄</button>
          </div>

          <div className="mt-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
            {TABLES.map((table) => (
              <div key={table} className="rounded-xl bg-[#F3EEE5] p-3 text-xs">
                <div className="font-mono text-[#68746B]">{table}</div>
                <div className="mt-1 text-lg font-semibold text-[#233B35]">{counts.get(table) ?? 0}</div>
              </div>
            ))}
          </div>

          <div className="mt-6 space-y-3">
            {events.length === 0 ? (
              <div className="rounded-2xl border border-dashed border-[#CFC7BA] p-8 text-center text-sm text-[#68746B]">目前沒有收到事件。</div>
            ) : events.map((event) => (
              <article key={event.id} className="rounded-2xl border border-[#DED7CB] p-4">
                <div className="flex flex-wrap gap-2 font-mono text-xs text-[#A06B59]">
                  <span>{event.receivedAt}</span><span>·</span><span>{event.table}</span><span>·</span><span>{event.eventType}</span>
                </div>
                <pre className="mt-3 max-h-80 overflow-auto whitespace-pre-wrap break-all rounded-xl bg-[#F3EEE5] p-4 text-[11px] leading-5 text-[#34453E]">{JSON.stringify({ new: event.newRow, old: event.oldRow }, null, 2)}</pre>
              </article>
            ))}
          </div>
        </section>
      </main>
    </div>
  );
}
