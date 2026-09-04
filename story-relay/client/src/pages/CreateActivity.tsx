import { FormEvent, useCallback, useEffect, useState } from "react";
import { ArrowLeft, BarChart3, CheckCircle2, Copy, DoorOpen, Download, Loader2, MoreHorizontal, OctagonX, Pencil, PlusCircle, RefreshCw, Trash2, X } from "lucide-react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";

type Activity = {
  id: string;
  code: string;
  name: string | null;
  status: string;
  created_at: string;
};

type CreateResult = {
  activity_id: string;
  code: string;
  group_id: string;
  story_id: string;
};

type TeacherCsvRow = {
  group_id: string;
  group_name: string;
  user_id: string;
  display_name: string | null;
  role: string;
  joined_at: string;
  left_at: string | null;
  rounds_selected: number;
  segments_written: number;
  total_characters: number;
  first_submission_at: string | null;
  last_submission_at: string | null;
};

function optionalInt(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

const csvCell = (value: string | number | null) => {
  let text = value == null ? "" : String(value);
  if (typeof value === "string" && /^\s*[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replace(/"/g, '""')}"`;
};

const safeFilePart = (value: string) => value.replace(/[\\/:*?"<>|]/g, "-").replace(/\s+/g, "-").slice(0, 80) || "activity";

export default function CreateActivity() {
  const [name, setName] = useState("");
  const [prompt, setPrompt] = useState("");
  const [initialText, setInitialText] = useState("");
  const [groupSize, setGroupSize] = useState("");
  const [timeLimit, setTimeLimit] = useState("");
  const [minWords, setMinWords] = useState("");
  const [maxWords, setMaxWords] = useState("");
  const [requiredSegments, setRequiredSegments] = useState("");
  const [deadline, setDeadline] = useState("");
  const [creating, setCreating] = useState(false);
  const [created, setCreated] = useState<CreateResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activities, setActivities] = useState<Activity[]>([]);
  const [loadingActivities, setLoadingActivities] = useState(true);
  const [isPlatformAdmin, setIsPlatformAdmin] = useState(false);
  const [enteringId, setEnteringId] = useState<string | null>(null);
  const [stoppingId, setStoppingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [menuId, setMenuId] = useState<string | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [savingRenameId, setSavingRenameId] = useState<string | null>(null);
  const [exportingCsvId, setExportingCsvId] = useState<string | null>(null);

  const loadActivities = useCallback(async () => {
    setLoadingActivities(true);
    const { data: sessionData } = await supabase.auth.getSession();
    const userId = sessionData.session?.user.id;
    if (!userId) {
      setError("找不到登入中的使用者。");
      setLoadingActivities(false);
      return;
    }

    const [{ data: adminAllowed }, { data, error: queryError }] = await Promise.all([
      supabase.rpc("is_platform_admin"),
      supabase
        .from("activities")
        .select("id, code, name, status, created_at")
        .eq("teacher_id", userId)
        .is("deleted_at", null)
        .order("created_at", { ascending: false }),
    ]);

    const allowed = Boolean(adminAllowed);
    setIsPlatformAdmin(allowed);
    if (!allowed) setGroupSize("");

    if (queryError) setError(queryError.message);
    else setActivities((data ?? []) as Activity[]);
    setLoadingActivities(false);
  }, []);

  useEffect(() => { void loadActivities(); }, [loadActivities]);

  const hostAtLimit = activities.length >= 3;

  const handleCreate = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (hostAtLimit) {
      setError("每個帳號最多可擔任 3 個未刪除活動的主持人。請先刪除一個活動後再建立新的活動。");
      return;
    }
    setCreating(true);
    setError(null);
    setCreated(null);
    const deadlineIso = deadline ? new Date(deadline).toISOString() : null;
    const { data, error: rpcError } = await supabase.rpc("create_activity", {
      p_name: name.trim() || null,
      p_prompt: prompt.trim() || null,
      p_initial_text: initialText.trim() || null,
      p_group_size: isPlatformAdmin ? optionalInt(groupSize) : null,
      p_time_limit_seconds: optionalInt(timeLimit),
      p_min_words: optionalInt(minWords),
      p_max_words: optionalInt(maxWords),
      p_required_segments: optionalInt(requiredSegments),
      p_deadline: deadlineIso,
    });
    if (rpcError) setError(rpcError.message);
    else if (!data || typeof data !== "object") setError("後端沒有回傳活動資料。");
    else {
      setCreated(data as CreateResult);
      await loadActivities();
    }
    setCreating(false);
  };

  const handleEnter = async (activity: Activity) => {
    setEnteringId(activity.id);
    setError(null);

    const { data: groupId, error: rpcError } = await supabase.rpc("join_activity_by_code", {
      p_code: activity.code,
    });

    if (rpcError) {
      setError(rpcError.message);
      setEnteringId(null);
      return;
    }

    if (!groupId || typeof groupId !== "string") {
      setError("加入活動成功，但後端沒有回傳小組 ID。");
      setEnteringId(null);
      return;
    }

    window.location.hash = `/room/${groupId}`;
  };

  const handleStop = async (activityId: string) => {
    setMenuId(null);
    if (!window.confirm("停止後，參與者不能再加入或提交新段落。已寫內容會保留，而且停止中的活動仍計入 3 個主持活動上限。確定停止？")) return;
    setStoppingId(activityId);
    setError(null);
    const { error: rpcError } = await supabase.rpc("stop_activity", { p_activity_id: activityId });
    if (rpcError) setError(rpcError.message);
    setStoppingId(null);
    await loadActivities();
  };

  const handleDelete = async (activity: Activity) => {
    setMenuId(null);
    if (!window.confirm(`刪除「${activity.name || "未命名活動"}」後，你將看不到此活動。平台管理者可在 30 天內恢復，之後會永久清除。確定刪除？`)) return;
    setDeletingId(activity.id);
    setError(null);
    const { error: rpcError } = await supabase.rpc("delete_platform_activity", { p_activity_id: activity.id });
    if (rpcError) setError(rpcError.message);
    else {
      if (renamingId === activity.id) {
        setRenamingId(null);
        setRenameValue("");
      }
      await loadActivities();
    }
    setDeletingId(null);
  };

  const beginRename = (activity: Activity) => {
    setMenuId(null);
    setRenamingId(activity.id);
    setRenameValue(activity.name ?? "");
    setError(null);
  };

  const handleRename = async (activityId: string) => {
    setSavingRenameId(activityId);
    setError(null);
    const { error: rpcError } = await supabase.rpc("rename_activity", {
      p_activity_id: activityId,
      p_new_name: renameValue.trim() || null,
    });
    if (rpcError) setError(rpcError.message);
    else {
      setRenamingId(null);
      setRenameValue("");
      await loadActivities();
    }
    setSavingRenameId(null);
  };

  const handleExportCsv = async (activity: Activity) => {
    setExportingCsvId(activity.id);
    setError(null);

    const { data, error: rpcError } = await supabase.rpc("get_teacher_activity_csv", { p_activity_id: activity.id });
    if (rpcError) {
      setError(rpcError.message);
      setExportingCsvId(null);
      return;
    }

    const rows = (data ?? []) as TeacherCsvRow[];
    const headers = ["小組", "參與者ID", "顯示名稱", "角色", "加入時間", "離開時間", "被選Round次數", "投稿段數", "總字元數", "首次投稿時間", "最後投稿時間"];
    const csvRows = [
      headers.map(csvCell).join(","),
      ...rows.map((row) => [
        row.group_name,
        row.user_id,
        row.display_name,
        row.role,
        row.joined_at,
        row.left_at,
        row.rounds_selected,
        row.segments_written,
        row.total_characters,
        row.first_submission_at,
        row.last_submission_at,
      ].map(csvCell).join(",")),
    ];

    const blob = new Blob(["\uFEFF", csvRows.join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${safeFilePart(activity.code)}-${safeFilePart(activity.name || "未命名活動")}-participants.csv`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 0);
    setExportingCsvId(null);
  };

  const copyCode = async (code: string) => navigator.clipboard.writeText(code);

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-5xl">
        <a href={import.meta.env.BASE_URL} className="inline-flex items-center gap-2 text-sm text-[#68746B] hover:text-[#233B35]"><ArrowLeft size={16} /> 回到入口</a>

        <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1.15fr)_minmax(300px,0.85fr)]">
          <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
            <div className="flex items-center gap-3"><PlusCircle size={22} className="text-[#A64E3C]" /><span className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">主持人區</span></div>
            <h1 className="mt-4 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35]">建立活動</h1>
            <p className="mt-4 text-sm leading-7 text-[#68746B]">全部欄位都非必要。限制欄位留白代表不設限；文字欄位留白就保持空白。</p>
            <div className={`mt-4 rounded-xl px-4 py-3 text-sm ${hostAtLimit ? "border border-[#E7C8BF] bg-[#F7E5DF] text-[#8D4033]" : "bg-[#EDF3EC] text-[#355447]"}`}>
              目前主持 <strong>{activities.length} / 3</strong> 個未刪除活動。停止中的活動也會計入；刪除後不再計入。
            </div>

            <form onSubmit={handleCreate} className="mt-8 space-y-6">
              <label className="block text-sm"><span className="mb-2 block font-semibold">活動名稱</span><input value={name} onChange={(e) => setName(e.target.value)} placeholder="可留白" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              {isPlatformAdmin && (
                <div className="rounded-2xl border border-[#D7C9B8] bg-[#F8F2E8] p-4">
                  <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-[#A06B59]">平台管理者 · 進階分組</div>
                  <label className="mt-3 block text-sm"><span className="mb-2 block font-semibold">每組人數</span><input type="number" min="1" value={groupSize} onChange={(e) => setGroupSize(e.target.value)} placeholder="留白 = 單一不限人數故事" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                  <p className="mt-2 text-xs leading-5 text-[#7B7268]">設定數字後，參與者會自動分入多個獨立故事小組。此功能目前只開放平台管理者。</p>
                </div>
              )}
              <label className="block text-sm"><span className="mb-2 block font-semibold">故事提示</span><textarea value={prompt} onChange={(e) => setPrompt(e.target.value)} placeholder="可留白" rows={3} className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              <label className="block text-sm"><span className="mb-2 block font-semibold">Writer 0 初始文字</span><textarea value={initialText} onChange={(e) => setInitialText(e.target.value)} placeholder="可留白；留白時故事從第一位參與者開始" rows={4} className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
                <label className="text-sm"><span className="mb-2 block font-semibold">每輪秒數</span><input type="number" min="1" value={timeLimit} onChange={(e) => setTimeLimit(e.target.value)} placeholder="不限" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">最少字數</span><input type="number" min="0" value={minWords} onChange={(e) => setMinWords(e.target.value)} placeholder="不限" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">最多字數</span><input type="number" min="0" value={maxWords} onChange={(e) => setMaxWords(e.target.value)} placeholder="不限" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">完成段落數</span><input type="number" min="1" value={requiredSegments} onChange={(e) => setRequiredSegments(e.target.value)} placeholder="不自動結束" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm sm:col-span-2"><span className="mb-2 block font-semibold">截止時間</span><input type="datetime-local" value={deadline} onChange={(e) => setDeadline(e.target.value)} className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              </div>
              <button type="submit" disabled={creating || loadingActivities || hostAtLimit} className="flex w-full items-center justify-center gap-2 rounded-xl bg-[#233B35] px-5 py-3 text-sm font-semibold text-[#FFFDF8] transition hover:bg-[#304D44] disabled:cursor-not-allowed disabled:opacity-45">
                {creating ? <Loader2 size={17} className="animate-spin" /> : <PlusCircle size={17} />}
                {creating ? "建立中…" : hostAtLimit ? "已達 3 個活動上限" : "建立活動"}
              </button>
            </form>

            {created && <div className="mt-6 rounded-2xl border border-[#CAD8CB] bg-[#EDF3EC] p-5 text-[#355447]"><div className="flex items-center gap-2 font-semibold"><CheckCircle2 size={18} />活動已建立並啟用</div><p className="mt-3 text-sm">把這個代碼提供給參與者：</p><div className="mt-2 flex items-center gap-2"><code className="rounded-lg bg-white/80 px-4 py-2 font-mono text-lg font-bold tracking-[0.08em]">{created.code}</code><button type="button" onClick={() => copyCode(created.code)} className="rounded-lg p-2 hover:bg-white" aria-label="複製活動代碼"><Copy size={17} /></button></div></div>}
            {error && <div className="mt-6 rounded-xl border border-[#E7C8BF] bg-[#F7E5DF] px-4 py-3 text-sm text-[#8D4033]"><div className="font-semibold">操作失敗</div><div className="mt-1 break-words font-mono text-xs">{error}</div></div>}
          </section>

          <aside className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-8 lg:sticky lg:top-8 lg:self-start">
            <div className="flex items-center justify-between"><div><div className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">情境式主持人身分</div><h2 className="mt-2 font-serif text-3xl font-semibold tracking-[-0.04em] text-[#233B35]">我的活動</h2></div><button type="button" onClick={() => void loadActivities()} className="rounded-full p-2 text-[#68746B] hover:bg-[#EEE8DE]" aria-label="重新整理"><RefreshCw size={17} /></button></div>
            <p className="mt-3 text-sm leading-6 text-[#68746B]">每個帳號最多主持 3 個未刪除活動。常用操作與該活動的 CSV 匯出保留在卡片上，管理操作收在更多選單中。</p>

            <div className="mt-6 space-y-3">
              {loadingActivities && <div className="flex items-center gap-2 text-sm text-[#68746B]"><Loader2 size={16} className="animate-spin" />載入中…</div>}
              {!loadingActivities && activities.length === 0 && <p className="rounded-xl bg-[#F3EEE5] p-4 text-sm text-[#68746B]">你還沒有建立任何活動。</p>}
              {activities.map((activity) => (
                <div key={activity.id} className="relative rounded-2xl border border-[#DED8CC] p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div><div className="font-semibold text-[#30463D]">{activity.name || "未命名活動"}</div><div className="mt-1 font-mono text-xs tracking-[0.08em] text-[#A06B59]">{activity.code}</div></div>
                    <span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold tracking-[0.08em] ${activity.status === "active" ? "bg-[#E7EFE5] text-[#456348]" : "bg-[#ECE9E3] text-[#77776F]"}`}>{activity.status === "active" ? "進行中" : "已停止"}</span>
                  </div>

                  <div className="mt-4 grid grid-cols-[1fr_auto_auto_auto] gap-2">
                    <button type="button" disabled={enteringId === activity.id || activity.status !== "active"} onClick={() => void handleEnter(activity)} className="flex items-center justify-center gap-2 rounded-lg bg-[#A64E3C] px-3 py-2 text-xs font-semibold text-white hover:bg-[#8F4033] disabled:opacity-60">{enteringId === activity.id ? <Loader2 size={14} className="animate-spin" /> : <DoorOpen size={14} />}加入活動</button>
                    <Link href={`/teacher/activity/${activity.id}`} className="flex items-center justify-center gap-2 rounded-lg border border-[#BFC8C1] px-3 py-2 text-xs font-semibold text-[#355447] hover:bg-[#EDF3EC]"><BarChart3 size={14} /><span className="hidden sm:inline">活動監控</span></Link>
                    <button type="button" disabled={exportingCsvId === activity.id} onClick={() => void handleExportCsv(activity)} className="flex items-center justify-center gap-1.5 rounded-lg border border-[#BFC8C1] px-3 py-2 text-xs font-semibold text-[#355447] hover:bg-[#EDF3EC] disabled:opacity-50" aria-label={`匯出 ${activity.name || "未命名活動"} CSV`}>
                      {exportingCsvId === activity.id ? <Loader2 size={14} className="animate-spin" /> : <Download size={14} />}
                      <span className="hidden sm:inline">CSV</span>
                    </button>
                    <button type="button" onClick={() => setMenuId(menuId === activity.id ? null : activity.id)} className="flex items-center justify-center rounded-lg border border-[#D5CEC2] px-3 py-2 text-[#56645C] hover:bg-[#F3EEE5]" aria-label="更多操作"><MoreHorizontal size={17} /></button>
                  </div>

                  {menuId === activity.id && (
                    <div className="absolute right-4 z-20 mt-2 w-44 overflow-hidden rounded-xl border border-[#D8D2C6] bg-[#FFFDF8] py-1 shadow-lg">
                      <button type="button" onClick={() => beginRename(activity)} className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-[#355447] hover:bg-[#F3EEE5]"><Pencil size={14} />更名</button>
                      {activity.status === "active" && <button type="button" disabled={stoppingId === activity.id} onClick={() => void handleStop(activity.id)} className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-[#8D4033] hover:bg-[#F7E5DF] disabled:opacity-60"><OctagonX size={14} />停止活動</button>}
                      <div className="my-1 border-t border-[#E3DDD2]" />
                      <button type="button" disabled={deletingId === activity.id} onClick={() => void handleDelete(activity)} className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm font-semibold text-[#8D4033] hover:bg-[#F7E5DF] disabled:opacity-60"><Trash2 size={14} />刪除活動</button>
                    </div>
                  )}

                  {renamingId === activity.id && (
                    <div className="mt-3 rounded-xl bg-[#F3EEE5] p-3">
                      <label className="text-xs font-semibold text-[#56645C]">新名稱（可留白）</label>
                      <input autoFocus value={renameValue} onChange={(e) => setRenameValue(e.target.value)} className="mt-2 w-full rounded-lg border border-[#CFC8BB] bg-white px-3 py-2 text-sm outline-none focus:border-[#355447]" />
                      <div className="mt-2 flex gap-2">
                        <button type="button" disabled={savingRenameId === activity.id} onClick={() => void handleRename(activity.id)} className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-[#355447] px-3 py-2 text-xs font-semibold text-white disabled:opacity-60">{savingRenameId === activity.id ? <Loader2 size={13} className="animate-spin" /> : <CheckCircle2 size={13} />}儲存更名</button>
                        <button type="button" onClick={() => { setRenamingId(null); setRenameValue(""); }} className="flex items-center justify-center rounded-lg border border-[#D5CEC2] px-3 py-2 text-[#68746B]" aria-label="取消更名"><X size={14} /></button>
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </aside>
        </div>
      </main>
    </div>
  );
}
