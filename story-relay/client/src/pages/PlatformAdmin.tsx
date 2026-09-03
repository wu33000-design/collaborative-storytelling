import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Activity, BookOpen, Download, Loader2, RefreshCw, RotateCcw, Search, ShieldCheck, Trash2, UserPlus, Users } from "lucide-react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";

type Tab = "overview" | "activities" | "members" | "admins";
type MemberStat = {
  user_id: string; display_name: string | null; login_email: string | null;
  activities_created: number; activities_joined: number; groups_joined: number;
  rounds_selected: number; segments_written: number; total_characters: number;
  first_joined_at: string | null; last_submission_at: string | null;
};
type Overview = { members: number; activities: number; active_activities: number; active_members_7d: number; segments: number; characters: number };
type ActivityStat = {
  activity_id: string; code: string; name: string | null; status: string; host_user_id: string;
  host_name: string | null; host_email: string | null; participant_count: number; group_count: number;
  segment_count: number; created_at: string; last_activity_at: string;
};
type DeletedActivity = {
  activity_id: string; code: string; name: string | null; previous_status: string | null; host_user_id: string;
  host_name: string | null; host_email: string | null; participant_count: number; group_count: number;
  segment_count: number; deleted_at: string; purge_after: string;
};
type MemberActivity = {
  activity_id: string; code: string; name: string | null; activity_status: string;
  relation: "host" | "participant" | "host_and_participant"; group_count: number;
  rounds_selected: number; segments_written: number; total_characters: number;
  first_joined_at: string | null; last_submission_at: string | null;
};
type PlatformAdminRow = { user_id: string; display_name: string | null; login_email: string | null; created_at: string; is_current_user: boolean };

const csvCell = (value: unknown) => `"${String(value ?? "").replace(/"/g, '""')}"`;
const formatDate = (value: string | null) => value ? new Date(value).toLocaleString() : "—";
const relationLabel = (value: MemberActivity["relation"]) => value === "host" ? "主持人" : value === "host_and_participant" ? "主持人＋參與者" : "參與者";
const daysLeft = (value: string) => Math.max(0, Math.ceil((new Date(value).getTime() - Date.now()) / 86400000));

export default function PlatformAdmin() {
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [members, setMembers] = useState<MemberStat[]>([]);
  const [activities, setActivities] = useState<ActivityStat[]>([]);
  const [deletedActivities, setDeletedActivities] = useState<DeletedActivity[]>([]);
  const [admins, setAdmins] = useState<PlatformAdminRow[]>([]);
  const [search, setSearch] = useState("");
  const [activitySearch, setActivitySearch] = useState("");
  const [showDeleted, setShowDeleted] = useState(false);
  const [selectedMember, setSelectedMember] = useState<MemberStat | null>(null);
  const [memberActivities, setMemberActivities] = useState<MemberActivity[]>([]);
  const [detailLoading, setDetailLoading] = useState(false);
  const [newAdminEmail, setNewAdminEmail] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data: allowed, error: allowedError } = await supabase.rpc("is_platform_admin");
    if (allowedError || !allowed) {
      setAuthorized(false);
      setError(allowedError?.message ?? null);
      setLoading(false);
      return;
    }
    setAuthorized(true);
    const [overviewResult, memberResult, activityResult, deletedResult, adminResult] = await Promise.all([
      supabase.rpc("get_platform_overview"),
      supabase.rpc("get_platform_member_stats"),
      supabase.rpc("get_platform_activity_stats"),
      supabase.rpc("get_platform_deleted_activities"),
      supabase.rpc("get_platform_admins"),
    ]);
    const firstError = overviewResult.error || memberResult.error || activityResult.error || deletedResult.error || adminResult.error;
    if (firstError) setError(firstError.message);
    setOverview((overviewResult.data as Overview | null) ?? null);
    setMembers((memberResult.data ?? []) as MemberStat[]);
    setActivities((activityResult.data ?? []) as ActivityStat[]);
    setDeletedActivities((deletedResult.data ?? []) as DeletedActivity[]);
    setAdmins((adminResult.data ?? []) as PlatformAdminRow[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const filteredMembers = useMemo(() => {
    const q = search.trim().toLowerCase();
    return !q ? members : members.filter((row) => `${row.display_name ?? ""} ${row.login_email ?? ""} ${row.user_id}`.toLowerCase().includes(q));
  }, [members, search]);

  const filteredActivities = useMemo(() => {
    const q = activitySearch.trim().toLowerCase();
    const source = showDeleted ? deletedActivities : activities;
    if (!q) return source;
    return source.filter((row) => `${row.name ?? ""} ${row.code} ${row.host_name ?? ""} ${row.host_email ?? ""}`.toLowerCase().includes(q));
  }, [activities, deletedActivities, activitySearch, showDeleted]);

  const exportCsv = () => {
    const header = ["user_id", "display_name", "login_email", "activities_created", "activities_joined", "groups_joined", "rounds_selected", "segments_written", "total_characters", "first_joined_at", "last_submission_at"];
    const lines = [header.map(csvCell).join(","), ...filteredMembers.map((row) => [row.user_id, row.display_name, row.login_email, row.activities_created, row.activities_joined, row.groups_joined, row.rounds_selected, row.segments_written, row.total_characters, row.first_joined_at, row.last_submission_at].map(csvCell).join(","))];
    const blob = new Blob(["\ufeff", lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `story-relay-member-stats-${new Date().toISOString().slice(0, 10)}.csv`; a.click(); URL.revokeObjectURL(url);
  };

  const deleteActivity = async (row: ActivityStat) => {
    if (!window.confirm(`刪除「${row.name || "未命名活動"}」後，活動會進入回收桶並保留 30 天。確定繼續？`)) return;
    const code = window.prompt(`請輸入活動代碼 ${row.code} 確認刪除：`);
    if (code !== row.code) return;
    setBusyId(row.activity_id); setError(null);
    const { error: rpcError } = await supabase.rpc("delete_platform_activity", { p_activity_id: row.activity_id });
    if (rpcError) setError(rpcError.message); else await load();
    setBusyId(null);
  };

  const restoreActivity = async (row: DeletedActivity) => {
    if (!window.confirm(`恢復「${row.name || "未命名活動"}」？原活動、小組、故事與紀錄都會原地恢復。`)) return;
    setBusyId(row.activity_id); setError(null);
    const { error: rpcError } = await supabase.rpc("restore_platform_activity", { p_activity_id: row.activity_id });
    if (rpcError) setError(rpcError.message); else await load();
    setBusyId(null);
  };

  const openMember = async (member: MemberStat) => {
    setSelectedMember(member); setDetailLoading(true); setError(null);
    const { data, error: detailError } = await supabase.rpc("get_platform_member_activities", { p_user_id: member.user_id });
    if (detailError) setError(detailError.message);
    setMemberActivities((data ?? []) as MemberActivity[]); setDetailLoading(false);
  };

  const addAdmin = async (event: FormEvent) => {
    event.preventDefault(); if (!newAdminEmail.trim()) return;
    setBusyId("admin-add"); setError(null);
    const { error: rpcError } = await supabase.rpc("add_platform_admin_by_email", { p_email: newAdminEmail.trim() });
    if (rpcError) setError(rpcError.message); else { setNewAdminEmail(""); await load(); }
    setBusyId(null);
  };

  const removeAdmin = async (row: PlatformAdminRow) => {
    if (!window.confirm(`確定移除 ${row.login_email || row.display_name || "這個帳號"} 的平台管理者權限？`)) return;
    setBusyId(row.user_id); setError(null);
    const { error: rpcError } = await supabase.rpc("remove_platform_admin", { p_user_id: row.user_id });
    if (rpcError) setError(rpcError.message); else await load();
    setBusyId(null);
  };

  if (loading) return <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]"><Loader2 className="animate-spin" size={28} /></div>;

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-7xl">
        <div className="flex items-center justify-between gap-4"><Link href="/" className="text-sm text-[#68746B]">← 回首頁</Link>{authorized && <button onClick={() => void load()} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B]"><RefreshCw size={14}/>重新整理</button>}</div>
        {!authorized ? <section className="mt-10 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-8"><ShieldCheck className="text-[#A64E3C]"/><h1 className="mt-5 font-serif text-3xl font-semibold">平台管理者權限</h1><p className="mt-3 text-sm text-[#68746B]">目前登入帳號沒有平台管理者權限。</p></section> : <>
          <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
            <div className="flex items-center gap-2 text-[#A64E3C]"><ShieldCheck size={18}/><span className="font-mono text-[10px] uppercase tracking-[0.16em]">Platform Administration</span></div>
            <h1 className="mt-3 font-serif text-4xl font-semibold">平台控制台</h1>
            <p className="mt-4 text-sm leading-7 text-[#68746B]">管理全站活動、參與者與平台管理者。已刪除活動進入 30 天回收桶，期間只有平台管理者可見並可恢復。</p>
            <div className="mt-7 flex flex-wrap gap-2">{(["overview","activities","members","admins"] as Tab[]).map((item) => <button key={item} onClick={() => setTab(item)} className={`rounded-full px-4 py-2 text-sm font-semibold ${tab===item?"bg-[#233B35] text-[#FFFDF8]":"bg-[#F3EEE5] text-[#56645C]"}`}>{item==="overview"?"總覽":item==="activities"?"活動管理":item==="members"?"參與者管理":"平台管理者"}</button>)}</div>
          </header>
          {error && <section className="mt-6 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-[#8D4033]"><div className="font-semibold">操作失敗</div><div className="mt-2 font-mono text-xs">{error}</div></section>}

          {tab==="overview" && overview && <section className="mt-6"><div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{[["平台成員",overview.members],["活動總數",overview.activities],["進行中活動",overview.active_activities],["近 7 日活躍成員",overview.active_members_7d],["累計提交段落",overview.segments],["累計提交字元",overview.characters]].map(([label,value]) => <div key={String(label)} className="rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5"><div className="text-xs text-[#7C827B]">{label}</div><div className="mt-2 font-serif text-3xl font-semibold">{value}</div></div>)}</div><div className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6"><div className="flex items-center gap-2"><Activity size={18}/><h2 className="font-serif text-xl font-semibold">最近活動</h2></div><div className="mt-4 space-y-3">{activities.slice(0,5).map(row => <div key={row.activity_id} className="flex items-center justify-between rounded-xl bg-[#F6F1E8] px-4 py-3"><div><div className="font-semibold">{row.name||"未命名活動"}</div><div className="text-xs text-[#7B827B]">{row.code} · {row.host_name||row.host_email||"未知"}</div></div><div className="text-right text-xs text-[#68746B]">{row.participant_count} 位參與者<br/>{formatDate(row.last_activity_at)}</div></div>)}</div></div></section>}

          {tab==="activities" && <section className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-4 border-b border-[#E3DDD2] p-6"><div><h2 className="font-serif text-2xl font-semibold">{showDeleted?"已刪除活動":"所有活動"}</h2><div className="mt-3 flex gap-2"><button onClick={()=>setShowDeleted(false)} className={`rounded-full px-3 py-1.5 text-xs font-semibold ${!showDeleted?"bg-[#355447] text-white":"bg-[#F3EEE5]"}`}>目前活動</button><button onClick={()=>setShowDeleted(true)} className={`rounded-full px-3 py-1.5 text-xs font-semibold ${showDeleted?"bg-[#8D4033] text-white":"bg-[#F3EEE5]"}`}>已刪除活動 ({deletedActivities.length})</button></div></div><label className="flex min-w-[260px] items-center gap-2 rounded-xl border border-[#CFC8BB] bg-white px-3 py-2"><Search size={15}/><input value={activitySearch} onChange={e=>setActivitySearch(e.target.value)} placeholder="搜尋名稱、代碼、主持人" className="w-full bg-transparent text-sm outline-none"/></label></div>
            <div className="overflow-x-auto"><table className="min-w-[1220px] w-full text-left text-sm"><thead className="bg-[#F3EEE5] text-[11px] text-[#777F77]"><tr><th className="px-5 py-3">活動</th><th className="px-4 py-3">主持人</th><th className="px-4 py-3">狀態</th><th className="px-4 py-3">參與者</th><th className="px-4 py-3">小組</th><th className="px-4 py-3">段落</th><th className="px-4 py-3">時間</th><th className="px-4 py-3 text-right">操作</th></tr></thead><tbody>
              {!showDeleted && (filteredActivities as ActivityStat[]).map(row => <tr key={row.activity_id} className="border-t border-[#EEE8DE]"><td className="px-5 py-4"><div className="font-semibold">{row.name||"未命名活動"}</div><div className="font-mono text-xs text-[#A06B59]">{row.code}</div></td><td className="px-4 py-4"><div>{row.host_name||"—"}</div><div className="font-mono text-[10px] text-[#7B827B]">{row.host_email||"尚未同步"}</div></td><td className="px-4 py-4">{row.status}</td><td className="px-4 py-4">{row.participant_count}</td><td className="px-4 py-4">{row.group_count}</td><td className="px-4 py-4">{row.segment_count}</td><td className="px-4 py-4 text-xs text-[#68746B]">{formatDate(row.last_activity_at)}</td><td className="min-w-[220px] px-4 py-4 text-right"><div className="flex justify-end gap-2"><Link href={`/admin/activity/${row.activity_id}/content`} className="inline-flex items-center gap-1.5 rounded-lg border border-[#BFC8C1] bg-[#FFFDF8] px-3 py-2 text-xs font-semibold text-[#355447] hover:bg-[#EDF3EC]"><BookOpen size={13}/>活動內容</Link><button disabled={busyId===row.activity_id} onClick={()=>void deleteActivity(row)} className="inline-flex items-center gap-1.5 rounded-lg border border-[#D7A89D] px-3 py-2 text-xs font-semibold text-[#8D4033] hover:bg-[#F7E5DF] disabled:opacity-50"><Trash2 size={13}/>刪除活動</button></div></td></tr>)}
              {showDeleted && (filteredActivities as DeletedActivity[]).map(row => <tr key={row.activity_id} className="border-t border-[#EEE8DE]"><td className="px-5 py-4"><div className="font-semibold">{row.name||"未命名活動"}</div><div className="font-mono text-xs text-[#A06B59]">{row.code}</div></td><td className="px-4 py-4"><div>{row.host_name||"—"}</div><div className="font-mono text-[10px] text-[#7B827B]">{row.host_email||"尚未同步"}</div></td><td className="px-4 py-4">原狀態：{row.previous_status||"closed"}</td><td className="px-4 py-4">{row.participant_count}</td><td className="px-4 py-4">{row.group_count}</td><td className="px-4 py-4">{row.segment_count}</td><td className="px-4 py-4 text-xs text-[#68746B]">刪除：{formatDate(row.deleted_at)}<br/>剩 {daysLeft(row.purge_after)} 天</td><td className="min-w-[220px] px-4 py-4 text-right"><div className="flex justify-end gap-2"><Link href={`/admin/activity/${row.activity_id}/content`} className="inline-flex items-center gap-1.5 rounded-lg border border-[#BFC8C1] bg-[#FFFDF8] px-3 py-2 text-xs font-semibold text-[#355447] hover:bg-[#EDF3EC]"><BookOpen size={13}/>活動內容</Link><button disabled={busyId===row.activity_id} onClick={()=>void restoreActivity(row)} className="inline-flex items-center gap-1.5 rounded-lg bg-[#355447] px-3 py-2 text-xs font-semibold text-white disabled:opacity-50"><RotateCcw size={13}/>恢復</button></div></td></tr>)}
              {filteredActivities.length===0 && <tr><td colSpan={8} className="px-6 py-10 text-center text-sm text-[#777F77]">{showDeleted?"目前回收桶是空的。":"目前沒有符合條件的活動。"}</td></tr>}
            </tbody></table></div>
          </section>}

          {tab==="members" && <section className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] shadow-sm"><div className="flex flex-wrap items-center justify-between gap-4 border-b border-[#E3DDD2] p-6"><div className="flex items-center gap-2"><Users size={18}/><h2 className="font-serif text-2xl font-semibold">參與者管理</h2></div><div className="flex gap-2"><label className="flex items-center gap-2 rounded-xl border border-[#CFC8BB] bg-white px-3 py-2"><Search size={15}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="搜尋姓名或 Email" className="outline-none"/></label><button onClick={exportCsv} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-4 py-2 text-sm font-semibold text-white"><Download size={15}/>CSV</button></div></div><div className="overflow-x-auto"><table className="min-w-[1050px] w-full text-left text-sm"><thead className="bg-[#F3EEE5] text-[11px]"><tr><th className="px-5 py-3">成員</th><th className="px-4 py-3">Email</th><th className="px-4 py-3">建立活動</th><th className="px-4 py-3">參加活動</th><th className="px-4 py-3">被選輪次</th><th className="px-4 py-3">提交段落</th><th className="px-4 py-3">最近提交</th></tr></thead><tbody>{filteredMembers.map(row=><tr key={row.user_id} onClick={()=>void openMember(row)} className="cursor-pointer border-t border-[#EEE8DE] hover:bg-[#FFFEFA]"><td className="px-5 py-4 font-semibold">{row.display_name||"未命名成員"}</td><td className="px-4 py-4 font-mono text-xs">{row.login_email||"尚未同步"}</td><td className="px-4 py-4">{row.activities_created}</td><td className="px-4 py-4">{row.activities_joined}</td><td className="px-4 py-4">{row.rounds_selected}</td><td className="px-4 py-4">{row.segments_written}</td><td className="px-4 py-4 text-xs">{formatDate(row.last_submission_at)}</td></tr>)}</tbody></table></div>{selectedMember && <div className="border-t border-[#E3DDD2] p-6"><h3 className="font-serif text-xl font-semibold">{selectedMember.display_name||selectedMember.login_email} 的活動</h3>{detailLoading?<Loader2 className="mt-4 animate-spin"/>:<div className="mt-4 space-y-2">{memberActivities.map(row=><div key={row.activity_id} className="rounded-xl bg-[#F6F1E8] p-4"><div className="font-semibold">{row.name||"未命名活動"} · {relationLabel(row.relation)}</div><div className="mt-1 text-xs text-[#68746B]">{row.code} · 提交 {row.segments_written} 段 · {row.total_characters} 字元</div></div>)}</div>}</div>}</section>}

          {tab==="admins" && <section className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm"><div className="flex items-center gap-2"><ShieldCheck size={18}/><h2 className="font-serif text-2xl font-semibold">平台管理者</h2></div><form onSubmit={addAdmin} className="mt-5 flex gap-2"><input type="email" value={newAdminEmail} onChange={e=>setNewAdminEmail(e.target.value)} placeholder="已登入過的平台帳號 Email" className="flex-1 rounded-xl border border-[#CFC8BB] px-4 py-3 outline-none"/><button disabled={busyId==="admin-add"} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-4 py-3 text-sm font-semibold text-white"><UserPlus size={15}/>新增</button></form><div className="mt-5 space-y-3">{admins.map(row=><div key={row.user_id} className="flex items-center justify-between rounded-xl bg-[#F6F1E8] p-4"><div><div className="font-semibold">{row.display_name||"未命名成員"}{row.is_current_user?"（目前帳號）":""}</div><div className="font-mono text-xs text-[#68746B]">{row.login_email||"尚未同步"}</div></div><button disabled={busyId===row.user_id} onClick={()=>void removeAdmin(row)} className="inline-flex items-center gap-1.5 rounded-lg border border-[#D7A89D] px-3 py-2 text-xs font-semibold text-[#8D4033]"><Trash2 size={13}/>移除</button></div>)}</div></section>}
        </>}
      </main>
    </div>
  );
}
