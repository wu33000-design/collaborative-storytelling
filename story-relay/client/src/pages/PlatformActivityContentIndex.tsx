import { BookOpen, Loader2, Search, ShieldCheck } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";

type ActivityRow = {
  activity_id: string;
  code: string;
  name: string | null;
  status?: string;
  previous_status?: string | null;
  host_name: string | null;
  host_email: string | null;
  participant_count: number;
  group_count: number;
  segment_count: number;
  deleted_at?: string;
  purge_after?: string;
};

export default function PlatformActivityContentIndex() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<ActivityRow[]>([]);
  const [search, setSearch] = useState("");

  useEffect(() => {
    let active = true;
    void (async () => {
      setLoading(true);
      setError(null);
      const { data: allowed, error: allowedError } = await supabase.rpc("is_platform_admin");
      if (!active) return;
      if (allowedError || !allowed) {
        setError(allowedError?.message || "目前帳號沒有平台管理者權限。");
        setLoading(false);
        return;
      }

      const [currentResult, deletedResult] = await Promise.all([
        supabase.rpc("get_platform_activity_stats"),
        supabase.rpc("get_platform_deleted_activities"),
      ]);
      if (!active) return;
      const firstError = currentResult.error || deletedResult.error;
      if (firstError) setError(firstError.message);
      setRows([...(currentResult.data ?? []), ...(deletedResult.data ?? [])] as ActivityRow[]);
      setLoading(false);
    })();
    return () => { active = false; };
  }, []);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter(row => `${row.name ?? ""} ${row.code} ${row.host_name ?? ""} ${row.host_email ?? ""}`.toLowerCase().includes(q));
  }, [rows, search]);

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-6xl">
        <Link href="/admin" className="text-sm text-[#68746B] hover:text-[#233B35]">← 回平台控制台</Link>
        <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
          <div className="flex items-center gap-2 text-[#A64E3C]"><ShieldCheck size={18}/><span className="font-mono text-[10px] uppercase tracking-[0.16em]">Platform content access</span></div>
          <h1 className="mt-3 font-serif text-4xl font-semibold">所有活動內容</h1>
          <p className="mt-4 text-sm leading-7 text-[#68746B]">平台管理者可唯讀檢視所有進行中、已停止與 30 天回收桶內的活動內容。檢視不會加入活動或改變任何參與紀錄。</p>
          <label className="mt-6 flex max-w-xl items-center gap-2 rounded-xl border border-[#CFC8BB] bg-white px-4 py-3"><Search size={16}/><input value={search} onChange={event => setSearch(event.target.value)} placeholder="搜尋活動名稱、代碼、主持人或 Email" className="w-full bg-transparent text-sm outline-none"/></label>
        </header>

        {loading && <div className="mt-6 flex items-center gap-2 rounded-2xl bg-[#FFFDF8] p-6 text-sm text-[#68746B]"><Loader2 size={17} className="animate-spin"/>載入活動中…</div>}
        {error && <div className="mt-6 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-sm text-[#8D4033]">{error}</div>}

        {!loading && !error && <section className="mt-6 space-y-3">
          {filtered.length === 0 && <div className="rounded-2xl bg-[#FFFDF8] p-6 text-sm text-[#68746B]">沒有符合條件的活動。</div>}
          {filtered.map(row => {
            const deleted = Boolean(row.deleted_at);
            return <div key={row.activity_id} className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5 shadow-sm">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2"><h2 className="font-serif text-xl font-semibold">{row.name || "未命名活動"}</h2><span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${deleted ? "bg-[#F7E5DF] text-[#8D4033]" : "bg-[#E7EFE5] text-[#456348]"}`}>{deleted ? "回收桶" : row.status === "active" ? "進行中" : "已停止"}</span></div>
                <div className="mt-1 font-mono text-xs text-[#A06B59]">{row.code}</div>
                <div className="mt-2 text-xs text-[#68746B]">主持人：{row.host_name || row.host_email || "未知"} · {row.group_count} 組 · {row.participant_count} 位參與者 · {row.segment_count} 段</div>
              </div>
              <Link href={`/admin/activity/${row.activity_id}/content`} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-4 py-2.5 text-sm font-semibold text-white hover:bg-[#304D44]"><BookOpen size={16}/>檢視內容</Link>
            </div>;
          })}
        </section>}
      </main>
    </div>
  );
}
