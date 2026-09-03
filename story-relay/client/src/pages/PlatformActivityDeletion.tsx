import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, Loader2, Search, Trash2 } from "lucide-react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";

type ActivityStat = {
  activity_id: string;
  code: string;
  name: string | null;
  status: string;
  host_name: string | null;
  host_email: string | null;
  participant_count: number;
  group_count: number;
  segment_count: number;
};

export default function PlatformActivityDeletion() {
  const [loading, setLoading] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [rows, setRows] = useState<ActivityStat[]>([]);
  const [search, setSearch] = useState("");
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data: allowed, error: allowedError } = await supabase.rpc("is_platform_admin");
    if (allowedError || !allowed) {
      setAuthorized(false);
      setError(allowedError?.message ?? "目前帳號沒有平台管理者權限。");
      setLoading(false);
      return;
    }
    setAuthorized(true);
    const { data, error: statsError } = await supabase.rpc("get_platform_activity_stats");
    if (statsError) setError(statsError.message);
    setRows((data ?? []) as ActivityStat[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((row) => `${row.name ?? ""} ${row.code} ${row.host_name ?? ""} ${row.host_email ?? ""}`.toLowerCase().includes(q));
  }, [rows, search]);

  const remove = async (row: ActivityStat) => {
    const label = row.name || "未命名活動";
    if (!window.confirm(`永久刪除「${label}」(${row.code})？\n\n此操作會刪除活動、小組、故事、段落、接力輪次、提名／登記與參與紀錄，而且無法復原。`)) return;
    const typed = window.prompt(`再次確認：請輸入活動代碼 ${row.code}`);
    if (typed?.trim().toUpperCase() !== row.code.toUpperCase()) return;

    setDeletingId(row.activity_id);
    setError(null);
    const { error: rpcError } = await supabase.rpc("delete_platform_activity", { p_activity_id: row.activity_id });
    if (rpcError) setError(rpcError.message);
    else await load();
    setDeletingId(null);
  };

  if (loading) return <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]"><Loader2 size={28} className="animate-spin" /></div>;

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-5xl">
        <Link href="/admin" className="inline-flex items-center gap-2 text-sm text-[#68746B] hover:text-[#233B35]"><ArrowLeft size={16} />回平台控制台</Link>

        <header className="mt-8 rounded-3xl border border-[#E2C4BC] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
          <div className="flex items-center gap-2 text-[#A64E3C]"><Trash2 size={20} /><span className="font-mono text-[10px] uppercase tracking-[0.16em]">Danger Zone</span></div>
          <h1 className="mt-3 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35]">永久刪除活動</h1>
          <p className="mt-4 max-w-3xl text-sm leading-7 text-[#68746B]">這裡只供平台管理者處理需要完全移除的活動。一般課堂結束請使用「停止活動」；永久刪除會移除該活動及其所有小組、故事、段落與接力紀錄，無法復原。</p>
        </header>

        {!authorized ? <div className="mt-6 rounded-2xl bg-[#F7E5DF] p-5 text-sm text-[#8D4033]">{error}</div> : (
          <section className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-4 border-b border-[#E3DDD2] p-6">
              <div><h2 className="font-serif text-2xl font-semibold">選擇活動</h2><p className="mt-1 text-xs text-[#7B827B]">共 {filtered.length} 筆</p></div>
              <label className="flex min-w-[280px] items-center gap-2 rounded-xl border border-[#CFC8BB] bg-white px-3 py-2"><Search size={15} className="text-[#8A8F86]" /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="搜尋活動名稱、代碼、主持人" className="w-full bg-transparent text-sm outline-none" /></label>
            </div>

            {error && <div className="m-5 rounded-xl border border-[#E7C8BF] bg-[#F7E5DF] p-4 text-sm text-[#8D4033]">{error}</div>}

            <div className="divide-y divide-[#EEE8DE]">
              {filtered.map((row) => (
                <div key={row.activity_id} className="flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <div className="font-semibold text-[#30463D]">{row.name || "未命名活動"}</div>
                    <div className="mt-1 font-mono text-xs text-[#A06B59]">{row.code}</div>
                    <div className="mt-2 text-xs text-[#7B827B]">主持人：{row.host_name || row.host_email || "未知"} · {row.participant_count} 位參與者 · {row.group_count} 組 · {row.segment_count} 段</div>
                  </div>
                  <button type="button" disabled={deletingId === row.activity_id} onClick={() => void remove(row)} className="inline-flex items-center justify-center gap-2 rounded-xl border border-[#D8AAA0] px-4 py-2.5 text-sm font-semibold text-[#9B4637] hover:bg-[#F7E5DF] disabled:opacity-50">{deletingId === row.activity_id ? <Loader2 size={15} className="animate-spin" /> : <Trash2 size={15} />}永久刪除</button>
                </div>
              ))}
              {filtered.length === 0 && <div className="p-8 text-center text-sm text-[#777F77]">沒有符合條件的活動。</div>}
            </div>
          </section>
        )}
      </main>
    </div>
  );
}
