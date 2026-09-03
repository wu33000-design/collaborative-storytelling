import { useCallback, useEffect, useMemo, useState } from "react";
import { Download, Loader2, RefreshCw, ShieldCheck, Users } from "lucide-react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";

type MemberStat = {
  user_id: string;
  display_name: string | null;
  login_email: string | null;
  activities_created: number;
  activities_joined: number;
  groups_joined: number;
  rounds_selected: number;
  segments_written: number;
  total_characters: number;
  first_joined_at: string | null;
  last_submission_at: string | null;
};

const csvCell = (value: unknown) => {
  const text = value == null ? "" : String(value);
  return `"${text.replace(/"/g, '""')}"`;
};

const formatDate = (value: string | null) => (value ? new Date(value).toLocaleString() : "—");

export default function PlatformAdmin() {
  const [loading, setLoading] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<MemberStat[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);

    const { data: allowed, error: allowedError } = await supabase.rpc("is_platform_admin");
    if (allowedError) {
      setAuthorized(false);
      setError(allowedError.message);
      setLoading(false);
      return;
    }

    if (!allowed) {
      setAuthorized(false);
      setRows([]);
      setLoading(false);
      return;
    }

    setAuthorized(true);
    const { data, error: statsError } = await supabase.rpc("get_platform_member_stats");
    if (statsError) {
      setError(statsError.message);
      setLoading(false);
      return;
    }

    setRows((data ?? []) as MemberStat[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const totals = useMemo(
    () => ({
      members: rows.length,
      activities: rows.reduce((sum, row) => sum + Number(row.activities_created || 0), 0),
      segments: rows.reduce((sum, row) => sum + Number(row.segments_written || 0), 0),
      characters: rows.reduce((sum, row) => sum + Number(row.total_characters || 0), 0),
    }),
    [rows],
  );

  const exportCsv = () => {
    const header = [
      "user_id",
      "display_name",
      "login_email",
      "activities_created",
      "activities_joined",
      "groups_joined",
      "rounds_selected",
      "segments_written",
      "total_characters",
      "first_joined_at",
      "last_submission_at",
    ];

    const lines = [
      header.map(csvCell).join(","),
      ...rows.map((row) =>
        [
          row.user_id,
          row.display_name ?? "",
          row.login_email ?? "",
          row.activities_created,
          row.activities_joined,
          row.groups_joined,
          row.rounds_selected,
          row.segments_written,
          row.total_characters,
          row.first_joined_at ?? "",
          row.last_submission_at ?? "",
        ]
          .map(csvCell)
          .join(","),
      ),
    ];

    const blob = new Blob(["\ufeff", lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `story-relay-member-stats-${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  };

  if (loading) {
    return <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]"><Loader2 className="animate-spin" size={28} /></div>;
  }

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-7xl">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <Link href="/" className="text-sm text-[#68746B] hover:text-[#233B35]">← 回首頁</Link>
          {authorized && (
            <button type="button" onClick={() => void load()} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B] hover:bg-[#E9E3D8]"><RefreshCw size={14} />重新整理</button>
          )}
        </div>

        {!authorized ? (
          <section className="mt-10 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-8 shadow-sm">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[#F3EEE5] text-[#A64E3C]"><ShieldCheck size={22} /></div>
            <h1 className="mt-5 font-serif text-3xl font-semibold text-[#233B35]">平台管理者權限</h1>
            <p className="mt-3 max-w-xl text-sm leading-7 text-[#68746B]">目前登入帳號沒有平台管理者權限。平台統計資料不會回傳給一般主持人或參與者。</p>
            {error && <div className="mt-5 rounded-2xl bg-[#F7E5DF] p-4 font-mono text-xs text-[#8D4033]">{error}</div>}
          </section>
        ) : (
          <>
            <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
              <div className="flex flex-wrap items-start justify-between gap-6">
                <div>
                  <div className="flex items-center gap-2 text-[#A64E3C]"><ShieldCheck size={18} /><span className="font-mono text-[10px] uppercase tracking-[0.16em]">Platform Administration</span></div>
                  <h1 className="mt-3 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35] sm:text-5xl">全站成員參與統計</h1>
                  <p className="mt-4 max-w-2xl text-sm leading-7 text-[#68746B]">每一列代表一個平台帳號，登入 Email 用來將參與紀錄對應到真實參與者身分。統計跨越該帳號建立與參加的所有活動，不包含故事正文。</p>
                </div>
                <button type="button" onClick={exportCsv} disabled={rows.length === 0} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-5 py-3 text-sm font-semibold text-[#FFFDF8] disabled:opacity-50"><Download size={16} />匯出 CSV</button>
              </div>
            </header>

            {error && <section className="mt-6 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-[#8D4033]"><div className="font-semibold">讀取統計失敗</div><div className="mt-2 break-words font-mono text-xs">{error}</div></section>}

            <section className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5"><div className="text-xs text-[#7C827B]">平台成員</div><div className="mt-2 font-serif text-3xl font-semibold">{totals.members}</div></div>
              <div className="rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5"><div className="text-xs text-[#7C827B]">已建立活動</div><div className="mt-2 font-serif text-3xl font-semibold">{totals.activities}</div></div>
              <div className="rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5"><div className="text-xs text-[#7C827B]">參與者提交段落</div><div className="mt-2 font-serif text-3xl font-semibold">{totals.segments}</div></div>
              <div className="rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5"><div className="text-xs text-[#7C827B]">累計提交字元</div><div className="mt-2 font-serif text-3xl font-semibold">{totals.characters}</div></div>
            </section>

            <section className="mt-6 overflow-hidden rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] shadow-sm">
              <div className="flex items-center gap-2 border-b border-[#E3DDD2] px-6 py-5"><Users size={18} className="text-[#355447]" /><h2 className="font-serif text-xl font-semibold">所有成員</h2></div>
              <div className="overflow-x-auto">
                <table className="min-w-[1320px] w-full border-collapse text-left text-sm">
                  <thead className="bg-[#F3EEE5] text-[11px] uppercase tracking-[0.08em] text-[#777F77]">
                    <tr>
                      <th className="px-5 py-3">成員</th><th className="px-4 py-3">登入 Email</th><th className="px-4 py-3">建立活動</th><th className="px-4 py-3">參加活動</th><th className="px-4 py-3">參加小組</th><th className="px-4 py-3">被選輪次</th><th className="px-4 py-3">提交段落</th><th className="px-4 py-3">提交字元</th><th className="px-4 py-3">首次加入</th><th className="px-4 py-3">最近提交</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((row) => (
                      <tr key={row.user_id} className="border-t border-[#EEE8DE] align-top">
                        <td className="px-5 py-4"><div className="font-semibold text-[#2E433B]">{row.display_name || "未命名成員"}</div><div className="mt-1 max-w-[210px] truncate font-mono text-[9px] text-[#91958F]" title={row.user_id}>{row.user_id}</div></td>
                        <td className="px-4 py-4"><div className="max-w-[260px] truncate font-mono text-xs text-[#3D5149]" title={row.login_email || ""}>{row.login_email || "尚未同步"}</div></td>
                        <td className="px-4 py-4">{row.activities_created}</td><td className="px-4 py-4">{row.activities_joined}</td><td className="px-4 py-4">{row.groups_joined}</td><td className="px-4 py-4">{row.rounds_selected}</td><td className="px-4 py-4">{row.segments_written}</td><td className="px-4 py-4">{row.total_characters}</td><td className="px-4 py-4 whitespace-nowrap text-xs text-[#68746B]">{formatDate(row.first_joined_at)}</td><td className="px-4 py-4 whitespace-nowrap text-xs text-[#68746B]">{formatDate(row.last_submission_at)}</td>
                      </tr>
                    ))}
                    {rows.length === 0 && <tr><td colSpan={10} className="px-6 py-10 text-center text-sm text-[#777F77]">目前沒有可匯出的成員資料。</td></tr>}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}
      </main>
    </div>
  );
}
