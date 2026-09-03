import { ArrowLeft, DoorOpen, Loader2, Monitor, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";

type Activity = {
  id: string;
  code: string;
  name: string | null;
  status: string;
  created_at: string;
};

export default function TeacherDashboardIndex() {
  const [activities, setActivities] = useState<Activity[]>([]);
  const [loading, setLoading] = useState(true);
  const [enteringId, setEnteringId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadActivities = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data: sessionData } = await supabase.auth.getSession();
    const userId = sessionData.session?.user.id;
    if (!userId) {
      setError("找不到登入中的使用者。");
      setLoading(false);
      return;
    }

    const { data, error: queryError } = await supabase
      .from("activities")
      .select("id, code, name, status, created_at")
      .eq("teacher_id", userId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false });

    if (queryError) setError(queryError.message);
    else setActivities((data ?? []) as Activity[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    void loadActivities();
  }, [loadActivities]);

  const handleEnter = async (activity: Activity) => {
    setEnteringId(activity.id);
    setError(null);

    const { data: sessionData } = await supabase.auth.getSession();
    const userId = sessionData.session?.user.id;
    if (!userId) {
      setError("找不到登入中的使用者。");
      setEnteringId(null);
      return;
    }

    const { data: memberships, error: membershipError } = await supabase
      .from("group_members")
      .select("group_id")
      .eq("user_id", userId)
      .is("left_at", null);
    if (membershipError) {
      setError(membershipError.message);
      setEnteringId(null);
      return;
    }

    const joinedGroupIds = (memberships ?? []).map((row) => row.group_id as string);
    let groupId: string | null = null;

    if (joinedGroupIds.length > 0) {
      const { data: joinedGroups, error: joinedGroupError } = await supabase
        .from("groups")
        .select("id")
        .eq("activity_id", activity.id)
        .in("id", joinedGroupIds)
        .order("created_at", { ascending: true })
        .limit(1);
      if (joinedGroupError) {
        setError(joinedGroupError.message);
        setEnteringId(null);
        return;
      }
      groupId = joinedGroups?.[0]?.id ?? null;
    }

    if (!groupId) {
      const { data: groups, error: groupError } = await supabase
        .from("groups")
        .select("id")
        .eq("activity_id", activity.id)
        .order("created_at", { ascending: true })
        .limit(1);
      if (groupError) {
        setError(groupError.message);
        setEnteringId(null);
        return;
      }
      groupId = groups?.[0]?.id ?? null;
    }

    if (!groupId) {
      setError("這個活動目前沒有可進入的小組。");
      setEnteringId(null);
      return;
    }

    window.location.hash = `/room/${groupId}`;
  };

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-4xl">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <Link href="/create" className="inline-flex items-center gap-2 text-sm text-[#68746B] hover:text-[#233B35]"><ArrowLeft size={16} />回到主持人區</Link>
          <button type="button" onClick={() => void loadActivities()} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B] hover:bg-[#E9E3D8]"><RefreshCw size={14} />重新整理</button>
        </div>

        <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
          <div className="flex items-center gap-3"><Monitor size={22} className="text-[#A64E3C]" /><span className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">主持人活動監控</span></div>
          <h1 className="mt-4 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35]">選擇要監控的活動</h1>
          <p className="mt-4 text-sm leading-7 text-[#68746B]">「監控」可查看所有小組進度；「進入活動」只用主持人權限查看故事，不會自動加入小組或影響接力統計。</p>
        </header>

        {error && <div className="mt-6 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-sm text-[#8D4033]">{error}</div>}

        <section className="mt-6 space-y-4">
          {loading && <div className="flex items-center gap-2 rounded-2xl bg-[#FFFDF8] p-5 text-sm text-[#68746B]"><Loader2 size={16} className="animate-spin" />載入活動中…</div>}
          {!loading && activities.length === 0 && <div className="rounded-2xl bg-[#FFFDF8] p-6 text-sm text-[#68746B]">目前沒有你建立的活動。</div>}
          {activities.map((activity) => (
            <div key={activity.id} className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-[#D8D2C6] bg-[#FFFDF8] p-5 shadow-sm">
              <div>
                <div className="font-serif text-xl font-semibold text-[#30463D]">{activity.name || "未命名活動"}</div>
                <div className="mt-1 font-mono text-xs tracking-[0.08em] text-[#A06B59]">{activity.code}</div>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${activity.status === "active" ? "bg-[#E7EFE5] text-[#456348]" : "bg-[#ECE9E3] text-[#77776F]"}`}>{activity.status}</span>
                <Link href={`/teacher/activity/${activity.id}`} className="rounded-lg border border-[#BFC8C1] px-3 py-2 text-xs font-semibold text-[#355447] hover:bg-[#EDF3EC]">監控</Link>
                <button type="button" disabled={enteringId === activity.id} onClick={() => void handleEnter(activity)} className="inline-flex items-center gap-1.5 rounded-lg bg-[#233B35] px-3 py-2 text-xs font-semibold text-white hover:bg-[#304D44] disabled:opacity-60">
                  {enteringId === activity.id ? <Loader2 size={14} className="animate-spin" /> : <DoorOpen size={14} />}
                  進入活動
                </button>
              </div>
            </div>
          ))}
        </section>
      </main>
    </div>
  );
}
