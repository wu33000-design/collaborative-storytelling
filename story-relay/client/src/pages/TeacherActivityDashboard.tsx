import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, BookOpen, Clock3, Loader2, RefreshCw, Users } from "lucide-react";
import { Link, useRoute } from "wouter";
import { supabase } from "@/lib/supabase";

type Activity = {
  id: string;
  code: string;
  name: string | null;
  status: string;
  deadline: string | null;
};

type GroupDashboardRow = {
  group_id: string;
  group_name: string;
  story_id: string;
  story_status: string;
  member_count: number;
  completed_segments: number;
  required_segments: number | null;
  current_round_no: number | null;
  current_round_status: string | null;
  current_writer_id: string | null;
  current_writer_name: string | null;
  last_activity_at: string;
};

const activityName = (value: string | null) => value || "未命名活動";

export default function TeacherActivityDashboard() {
  const [, params] = useRoute("/teacher/activity/:activityId");
  const activityId = params?.activityId;
  const [activity, setActivity] = useState<Activity | null>(null);
  const [groups, setGroups] = useState<GroupDashboardRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadDashboard = useCallback(async (silent = false) => {
    if (!activityId) {
      setError("找不到活動 ID。");
      setLoading(false);
      return;
    }

    if (!silent) setLoading(true);
    setError(null);

    const [activityResult, dashboardResult] = await Promise.all([
      supabase
        .from("activities")
        .select("id, code, name, status, deadline")
        .eq("id", activityId)
        .maybeSingle(),
      supabase.rpc("get_teacher_activity_dashboard", { p_activity_id: activityId }),
    ]);

    if (activityResult.error || dashboardResult.error) {
      setError(activityResult.error?.message || dashboardResult.error?.message || "讀取教師監控資料失敗。");
      setLoading(false);
      return;
    }

    if (!activityResult.data) {
      setError("找不到這個活動，或你不是活動建立者。");
      setLoading(false);
      return;
    }

    setActivity(activityResult.data as Activity);
    setGroups((dashboardResult.data ?? []) as GroupDashboardRow[]);
    setLoading(false);
  }, [activityId]);

  useEffect(() => {
    void loadDashboard();
  }, [loadDashboard]);

  useEffect(() => {
    if (!activityId) return;

    const channel = supabase
      .channel(`teacher-dashboard:${activityId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "activity_events", filter: `activity_id=eq.${activityId}` },
        () => void loadDashboard(true),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "activities", filter: `id=eq.${activityId}` },
        () => void loadDashboard(true),
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [activityId, loadDashboard]);

  const summary = useMemo(() => {
    return {
      groups: groups.length,
      members: groups.reduce((sum, group) => sum + Number(group.member_count || 0), 0),
      completed: groups.filter((group) => group.story_status === "completed").length,
      writing: groups.filter((group) => group.current_round_status === "writing" || group.current_round_status === "open").length,
    };
  }, [groups]);

  if (loading) {
    return <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]"><Loader2 className="animate-spin" size={28} /></div>;
  }

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-6xl">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <Link href="/create" className="inline-flex items-center gap-2 text-sm text-[#68746B] hover:text-[#233B35]"><ArrowLeft size={16} />回到老師區</Link>
          <button type="button" onClick={() => void loadDashboard()} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B] hover:bg-[#E9E3D8]"><RefreshCw size={14} />重新整理</button>
        </div>

        {error && (
          <section className="mt-8 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-[#8D4033]">
            <div className="font-semibold">監控資料讀取失敗</div>
            <div className="mt-2 break-words font-mono text-xs">{error}</div>
          </section>
        )}

        {activity && (
          <>
            <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
              <div className="flex flex-wrap items-start justify-between gap-5">
                <div>
                  <div className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">教師活動監控 · {activity.code}</div>
                  <h1 className="mt-3 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35] sm:text-5xl">{activityName(activity.name)}</h1>
                  <p className="mt-4 text-sm leading-7 text-[#68746B]">即時查看所有小組的接力狀態。學生提交段落、換棒或故事完成後，此頁會自動更新。</p>
                </div>
                <span className={`rounded-full px-3 py-1.5 text-xs font-semibold ${activity.status === "active" ? "bg-[#E7EFE5] text-[#456348]" : "bg-[#ECE9E3] text-[#77776F]"}`}>{activity.status}</span>
              </div>

              <div className="mt-7 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <div className="rounded-2xl bg-[#F3EEE5] p-4"><div className="text-xs text-[#7B827B]">小組</div><div className="mt-1 font-serif text-3xl font-semibold text-[#30463D]">{summary.groups}</div></div>
                <div className="rounded-2xl bg-[#F3EEE5] p-4"><div className="text-xs text-[#7B827B]">目前學生</div><div className="mt-1 font-serif text-3xl font-semibold text-[#30463D]">{summary.members}</div></div>
                <div className="rounded-2xl bg-[#F3EEE5] p-4"><div className="text-xs text-[#7B827B]">正在接力</div><div className="mt-1 font-serif text-3xl font-semibold text-[#30463D]">{summary.writing}</div></div>
                <div className="rounded-2xl bg-[#F3EEE5] p-4"><div className="text-xs text-[#7B827B]">完成故事</div><div className="mt-1 font-serif text-3xl font-semibold text-[#30463D]">{summary.completed}</div></div>
              </div>
            </header>

            <section className="mt-7">
              <div className="flex items-center gap-2"><Users size={19} className="text-[#355447]" /><h2 className="font-serif text-2xl font-semibold text-[#30463D]">小組進度</h2></div>

              {groups.length === 0 ? (
                <div className="mt-5 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-8 text-sm text-[#68746B] shadow-sm">目前還沒有小組資料。學生加入後會出現在這裡。</div>
              ) : (
                <div className="mt-5 grid gap-5 md:grid-cols-2 xl:grid-cols-3">
                  {groups.map((group) => {
                    const required = group.required_segments;
                    const progress = required && required > 0 ? Math.min(100, Math.round((group.completed_segments / required) * 100)) : null;
                    const isActive = group.story_status === "active";
                    const hasRound = group.current_round_no != null;

                    return (
                      <article key={group.group_id} className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <div className="font-serif text-2xl font-semibold text-[#30463D]">{group.group_name}</div>
                            <div className="mt-1 text-xs text-[#7B827B]">{group.member_count} 位學生</div>
                          </div>
                          <span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${group.story_status === "completed" ? "bg-[#DDE9DE] text-[#355447]" : isActive ? "bg-[#F3E9D9] text-[#8B5E37]" : "bg-[#ECE9E3] text-[#77776F]"}`}>{group.story_status}</span>
                        </div>

                        <div className="mt-5 rounded-2xl bg-[#F6F1E8] p-4">
                          <div className="flex items-center justify-between gap-3 text-xs text-[#68746B]"><span>已完成段落</span><strong className="font-mono text-[#30463D]">{group.completed_segments}{required != null ? ` / ${required}` : ""}</strong></div>
                          {progress != null && <div className="mt-3 h-2 overflow-hidden rounded-full bg-[#E0D9CE]"><div className="h-full rounded-full bg-[#6B8F71]" style={{ width: `${progress}%` }} /></div>}
                        </div>

                        <div className="mt-4 space-y-3 text-sm">
                          <div className="flex items-center justify-between gap-3"><span className="text-[#7B827B]">目前 Round</span><span className="font-semibold text-[#30463D]">{hasRound ? `#${group.current_round_no} · ${group.current_round_status}` : "尚未開始"}</span></div>
                          <div className="flex items-center justify-between gap-3"><span className="text-[#7B827B]">目前作者</span><span className="max-w-[55%] truncate font-semibold text-[#30463D]">{group.current_writer_name || (hasRound ? "參與者" : "—")}</span></div>
                          <div className="flex items-center justify-between gap-3"><span className="inline-flex items-center gap-1.5 text-[#7B827B]"><Clock3 size={13} />最後活動</span><span className="text-right text-xs text-[#56645C]">{new Date(group.last_activity_at).toLocaleString()}</span></div>
                        </div>

                        <Link href={`/room/${group.group_id}`} className="mt-5 flex w-full items-center justify-center gap-2 rounded-xl bg-[#233B35] px-4 py-2.5 text-sm font-semibold text-[#FFFDF8] hover:bg-[#304D44]"><BookOpen size={15} />進入故事</Link>
                      </article>
                    );
                  })}
                </div>
              )}
            </section>
          </>
        )}
      </main>
    </div>
  );
}
