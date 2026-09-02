import { FormEvent, useCallback, useEffect, useState } from "react";
import { ArrowLeft, CheckCircle2, Copy, Loader2, OctagonX, PlusCircle, RefreshCw } from "lucide-react";
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

function optionalInt(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

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
  const [stoppingId, setStoppingId] = useState<string | null>(null);

  const loadActivities = useCallback(async () => {
    setLoadingActivities(true);
    const { data: sessionData } = await supabase.auth.getSession();
    const userId = sessionData.session?.user.id;

    if (!userId) {
      setError("找不到登入中的使用者。");
      setLoadingActivities(false);
      return;
    }

    const { data, error: queryError } = await supabase
      .from("activities")
      .select("id, code, name, status, created_at")
      .eq("teacher_id", userId)
      .order("created_at", { ascending: false });

    if (queryError) {
      setError(queryError.message);
    } else {
      setActivities((data ?? []) as Activity[]);
    }
    setLoadingActivities(false);
  }, []);

  useEffect(() => {
    void loadActivities();
  }, [loadActivities]);

  const handleCreate = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setCreating(true);
    setError(null);
    setCreated(null);

    const deadlineIso = deadline ? new Date(deadline).toISOString() : null;

    const { data, error: rpcError } = await supabase.rpc("create_activity", {
      p_name: name.trim() || null,
      p_prompt: prompt.trim() || null,
      p_initial_text: initialText.trim() || null,
      p_group_size: optionalInt(groupSize),
      p_time_limit_seconds: optionalInt(timeLimit),
      p_min_words: optionalInt(minWords),
      p_max_words: optionalInt(maxWords),
      p_required_segments: optionalInt(requiredSegments),
      p_deadline: deadlineIso,
    });

    if (rpcError) {
      setError(rpcError.message);
      setCreating(false);
      return;
    }

    if (!data || typeof data !== "object") {
      setError("後端沒有回傳活動資料。");
      setCreating(false);
      return;
    }

    setCreated(data as CreateResult);
    setCreating(false);
    await loadActivities();
  };

  const handleStop = async (activityId: string) => {
    if (!window.confirm("停止後，玩家不能再加入或提交新段落。已寫內容會保留。確定停止？")) return;

    setStoppingId(activityId);
    setError(null);
    const { error: rpcError } = await supabase.rpc("stop_activity", { p_activity_id: activityId });
    if (rpcError) {
      setError(rpcError.message);
    }
    setStoppingId(null);
    await loadActivities();
  };

  const copyCode = async (code: string) => {
    await navigator.clipboard.writeText(code);
  };

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-5xl">
        <a href={import.meta.env.BASE_URL} className="inline-flex items-center gap-2 text-sm text-[#68746B] hover:text-[#233B35]"><ArrowLeft size={16} /> 回到入口</a>

        <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1.15fr)_minmax(300px,0.85fr)]">
          <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
            <div className="flex items-center gap-3"><PlusCircle size={22} className="text-[#A64E3C]" /><span className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">老師區</span></div>
            <h1 className="mt-4 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35]">建立活動</h1>
            <p className="mt-4 text-sm leading-7 text-[#68746B]">全部欄位都非必要。限制欄位留白代表不設限；文字欄位留白就保持空白。</p>

            <form onSubmit={handleCreate} className="mt-8 space-y-6">
              <div className="grid gap-5 sm:grid-cols-2">
                <label className="text-sm"><span className="mb-2 block font-semibold">活動名稱</span><input value={name} onChange={(e) => setName(e.target.value)} placeholder="可留白" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">每組人數</span><input type="number" min="1" value={groupSize} onChange={(e) => setGroupSize(e.target.value)} placeholder="留白 = 不限人數" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              </div>

              <label className="block text-sm"><span className="mb-2 block font-semibold">故事提示</span><textarea value={prompt} onChange={(e) => setPrompt(e.target.value)} placeholder="可留白" rows={3} className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              <label className="block text-sm"><span className="mb-2 block font-semibold">Writer 0 初始文字</span><textarea value={initialText} onChange={(e) => setInitialText(e.target.value)} placeholder="可留白；留白時故事從第一位玩家開始" rows={4} className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>

              <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
                <label className="text-sm"><span className="mb-2 block font-semibold">每輪秒數</span><input type="number" min="1" value={timeLimit} onChange={(e) => setTimeLimit(e.target.value)} placeholder="不限" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">最少字數</span><input type="number" min="0" value={minWords} onChange={(e) => setMinWords(e.target.value)} placeholder="不限" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">最多字數</span><input type="number" min="0" value={maxWords} onChange={(e) => setMaxWords(e.target.value)} placeholder="不限" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm"><span className="mb-2 block font-semibold">完成段落數</span><input type="number" min="1" value={requiredSegments} onChange={(e) => setRequiredSegments(e.target.value)} placeholder="不自動結束" className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
                <label className="text-sm sm:col-span-2"><span className="mb-2 block font-semibold">截止時間</span><input type="datetime-local" value={deadline} onChange={(e) => setDeadline(e.target.value)} className="w-full rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 outline-none focus:border-[#355447]" /></label>
              </div>

              <button type="submit" disabled={creating} className="flex w-full items-center justify-center gap-2 rounded-xl bg-[#233B35] px-5 py-3 text-sm font-semibold text-[#FFFDF8] transition hover:bg-[#304D44] disabled:opacity-60">
                {creating ? <Loader2 size={17} className="animate-spin" /> : <PlusCircle size={17} />}
                {creating ? "建立中…" : "建立活動"}
              </button>
            </form>

            {created && <div className="mt-6 rounded-2xl border border-[#CAD8CB] bg-[#EDF3EC] p-5 text-[#355447]"><div className="flex items-center gap-2 font-semibold"><CheckCircle2 size={18} />活動已建立並啟用</div><p className="mt-3 text-sm">把這個代碼提供給玩家：</p><div className="mt-2 flex items-center gap-2"><code className="rounded-lg bg-white/80 px-4 py-2 font-mono text-lg font-bold tracking-[0.08em]">{created.code}</code><button type="button" onClick={() => copyCode(created.code)} className="rounded-lg p-2 hover:bg-white" aria-label="複製活動代碼"><Copy size={17} /></button></div></div>}
            {error && <div className="mt-6 rounded-xl border border-[#E7C8BF] bg-[#F7E5DF] px-4 py-3 text-sm text-[#8D4033]"><div className="font-semibold">操作失敗</div><div className="mt-1 break-words font-mono text-xs">{error}</div></div>}
          </section>

          <aside className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-8 lg:sticky lg:top-8 lg:self-start">
            <div className="flex items-center justify-between"><div><div className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">情境式老師身分</div><h2 className="mt-2 font-serif text-3xl font-semibold tracking-[-0.04em] text-[#233B35]">我的活動</h2></div><button type="button" onClick={() => void loadActivities()} className="rounded-full p-2 text-[#68746B] hover:bg-[#EEE8DE]" aria-label="重新整理"><RefreshCw size={17} /></button></div>
            <p className="mt-3 text-sm leading-6 text-[#68746B]">你建立的活動會出現在這裡。活動進行中時，玩家可以中途加入；你也可以隨時手動停止。</p>

            <div className="mt-6 space-y-3">
              {loadingActivities && <div className="flex items-center gap-2 text-sm text-[#68746B]"><Loader2 size={16} className="animate-spin" />載入中…</div>}
              {!loadingActivities && activities.length === 0 && <p className="rounded-xl bg-[#F3EEE5] p-4 text-sm text-[#68746B]">你還沒有建立任何活動。</p>}
              {activities.map((activity) => (
                <div key={activity.id} className="rounded-2xl border border-[#DED8CC] p-4">
                  <div className="flex items-start justify-between gap-3"><div><div className="font-semibold text-[#30463D]">{activity.name || "未命名活動"}</div><div className="mt-1 font-mono text-xs tracking-[0.08em] text-[#A06B59]">{activity.code}</div></div><span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.08em] ${activity.status === "active" ? "bg-[#E7EFE5] text-[#456348]" : "bg-[#ECE9E3] text-[#77776F]"}`}>{activity.status}</span></div>
                  {activity.status === "active" && <button type="button" disabled={stoppingId === activity.id} onClick={() => void handleStop(activity.id)} className="mt-4 flex w-full items-center justify-center gap-2 rounded-lg border border-[#D8AAA0] px-3 py-2 text-xs font-semibold text-[#9B4637] hover:bg-[#F7E5DF] disabled:opacity-60">{stoppingId === activity.id ? <Loader2 size={14} className="animate-spin" /> : <OctagonX size={14} />}停止活動</button>}
                </div>
              ))}
            </div>
          </aside>
        </div>
      </main>
    </div>
  );
}
