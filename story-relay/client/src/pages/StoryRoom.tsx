import { useCallback, useEffect, useMemo, useState } from "react";
import { BookOpen, Clock3, History, Loader2, Play, RefreshCw, Users } from "lucide-react";
import { Link, useRoute } from "wouter";
import { supabase } from "@/lib/supabase";

type Activity = { id: string; code: string; name: string | null; prompt: string | null; status: string };
type Group = { id: string; name: string; activity_id: string };
type Story = { id: string; title: string | null; prompt: string | null; status: string };
type Segment = { id: string; sequence_no: number; author_id: string | null; content: string; submitted_at: string };
type Member = { user_id: string; role: string; joined_at: string };
type Profile = { id: string; display_name: string; avatar_url: string | null };
type NameHistory = { id: string; old_name: string | null; new_name: string | null; changed_at: string };
type RelayRound = { id: string; round_no: number; current_writer_id: string; status: string };

const displayName = (value: string | null) => value || "未命名活動";

export default function StoryRoom() {
  const [, params] = useRoute("/room/:groupId");
  const groupId = params?.groupId;
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [group, setGroup] = useState<Group | null>(null);
  const [activity, setActivity] = useState<Activity | null>(null);
  const [story, setStory] = useState<Story | null>(null);
  const [segments, setSegments] = useState<Segment[]>([]);
  const [members, setMembers] = useState<Member[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [history, setHistory] = useState<NameHistory[]>([]);
  const [round, setRound] = useState<RelayRound | null>(null);
  const [startingRound, setStartingRound] = useState(false);

  const profileMap = useMemo(() => new Map(profiles.map((profile) => [profile.id, profile])), [profiles]);

  const loadRoom = useCallback(async () => {
    if (!groupId) {
      setError("找不到小組 ID。");
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    const { data: groupData, error: groupError } = await supabase
      .from("groups")
      .select("id, name, activity_id")
      .eq("id", groupId)
      .maybeSingle();

    if (groupError || !groupData) {
      setError(groupError?.message || "找不到這個小組，或你沒有存取權限。");
      setLoading(false);
      return;
    }

    const loadedGroup = groupData as Group;
    setGroup(loadedGroup);

    const [activityResult, storyResult, memberResult, historyResult] = await Promise.all([
      supabase.from("activities").select("id, code, name, prompt, status").eq("id", loadedGroup.activity_id).maybeSingle(),
      supabase.from("stories").select("id, title, prompt, status").eq("group_id", loadedGroup.id).maybeSingle(),
      supabase.from("group_members").select("user_id, role, joined_at").eq("group_id", loadedGroup.id).is("left_at", null).order("joined_at"),
      supabase.from("activity_name_history").select("id, old_name, new_name, changed_at").eq("activity_id", loadedGroup.activity_id).order("changed_at", { ascending: true }),
    ]);

    const firstError = activityResult.error || storyResult.error || memberResult.error || historyResult.error;
    if (firstError) {
      setError(firstError.message);
      setLoading(false);
      return;
    }

    const loadedActivity = activityResult.data as Activity | null;
    const loadedStory = storyResult.data as Story | null;
    const loadedMembers = (memberResult.data ?? []) as Member[];

    if (!loadedActivity || !loadedStory) {
      setError("活動或故事資料不完整。");
      setLoading(false);
      return;
    }

    setActivity(loadedActivity);
    setStory(loadedStory);
    setMembers(loadedMembers);
    setHistory((historyResult.data ?? []) as NameHistory[]);

    const [segmentResult, profileResult, roundResult] = await Promise.all([
      supabase.from("segments").select("id, sequence_no, author_id, content, submitted_at").eq("story_id", loadedStory.id).order("sequence_no"),
      loadedMembers.length > 0
        ? supabase.from("profiles").select("id, display_name, avatar_url").in("id", loadedMembers.map((member) => member.user_id))
        : Promise.resolve({ data: [], error: null }),
      supabase.from("relay_rounds").select("id, round_no, current_writer_id, status").eq("story_id", loadedStory.id).in("status", ["open", "writing"]).order("round_no", { ascending: false }).limit(1).maybeSingle(),
    ]);

    if (segmentResult.error || profileResult.error || roundResult.error) {
      setError(segmentResult.error?.message || profileResult.error?.message || roundResult.error?.message || "讀取房間資料失敗。");
      setLoading(false);
      return;
    }

    setSegments((segmentResult.data ?? []) as Segment[]);
    setProfiles((profileResult.data ?? []) as Profile[]);
    setRound((roundResult.data as RelayRound | null) ?? null);
    setLoading(false);
  }, [groupId]);

  useEffect(() => {
    void loadRoom();
  }, [loadRoom]);

  const handleStartRound = async () => {
    if (!groupId) return;
    setStartingRound(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc("start_relay_round", { p_group_id: groupId });
    if (rpcError) setError(rpcError.message);
    setStartingRound(false);
    await loadRoom();
  };

  if (loading) {
    return <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]"><Loader2 className="animate-spin" size={28} /></div>;
  }

  const currentWriter = round ? profileMap.get(round.current_writer_id) : null;

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-5xl">
        <div className="flex items-center justify-between gap-4">
          <Link href="/join" className="text-sm text-[#68746B] hover:text-[#233B35]">← 回到加入活動</Link>
          <button type="button" onClick={() => void loadRoom()} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B] hover:bg-[#E9E3D8]"><RefreshCw size={14} />重新整理</button>
        </div>

        {error ? (
          <section className="mt-8 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-[#8D4033]">
            <div className="font-semibold">房間操作失敗</div>
            <div className="mt-2 break-words font-mono text-xs">{error}</div>
          </section>
        ) : activity && group && story ? (
          <>
            <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
              <div className="flex flex-wrap items-start justify-between gap-5">
                <div>
                  <div className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">{activity.code} · {group.name}</div>
                  <h1 className="mt-3 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35] sm:text-5xl">{displayName(activity.name)}</h1>
                  <p className="mt-4 max-w-2xl text-sm leading-7 text-[#68746B]">{activity.prompt || story.prompt || "老師沒有設定故事提示。"}</p>
                </div>
                <span className="rounded-full bg-[#E7EFE5] px-3 py-1.5 text-xs font-semibold text-[#456348]">{activity.status}</span>
              </div>

              <div className="mt-6 rounded-2xl bg-[#F3EEE5] p-5">
                {round ? (
                  <div className="flex flex-wrap items-center justify-between gap-4">
                    <div><div className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#A06B59]">Round {round.round_no} · {round.status}</div><div className="mt-1 text-sm text-[#34453E]">目前作者：<span className="font-semibold">{currentWriter?.display_name || "參與者"}</span></div></div>
                  </div>
                ) : (
                  <div className="flex flex-wrap items-center justify-between gap-4"><div><div className="font-semibold text-[#30463D]">接力尚未開始</div><div className="mt-1 text-xs leading-5 text-[#68746B]">開始後，後端會依目前 selection weight 抽出第一位作者。</div></div><button type="button" disabled={startingRound || activity.status !== "active"} onClick={() => void handleStartRound()} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-4 py-2.5 text-sm font-semibold text-[#FFFDF8] disabled:opacity-60">{startingRound ? <Loader2 size={15} className="animate-spin" /> : <Play size={15} />}開始第一輪</button></div>
                )}
              </div>
            </header>

            <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1.45fr)_minmax(280px,0.75fr)]">
              <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-8">
                <div className="flex items-center gap-2"><BookOpen size={19} className="text-[#A64E3C]" /><h2 className="font-serif text-2xl font-semibold">目前故事</h2></div>
                {segments.length === 0 ? (
                  <p className="mt-6 rounded-2xl bg-[#F3EEE5] p-5 text-sm leading-7 text-[#68746B]">目前還沒有任何段落。</p>
                ) : (
                  <div className="mt-6 space-y-5">
                    {segments.map((segment) => (
                      <article key={segment.id} className="border-l-2 border-[#D8D2C6] pl-5">
                        <div className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#A06B59]">#{segment.sequence_no} · {segment.author_id ? profileMap.get(segment.author_id)?.display_name || "參與者" : "Writer 0"}</div>
                        <p className="mt-2 whitespace-pre-wrap text-[15px] leading-8 text-[#34453E]">{segment.content}</p>
                      </article>
                    ))}
                  </div>
                )}
              </section>

              <aside className="space-y-6">
                <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm">
                  <div className="flex items-center gap-2"><Users size={18} className="text-[#355447]" /><h2 className="font-serif text-xl font-semibold">小組成員</h2></div>
                  <div className="mt-4 space-y-3">
                    {members.map((member) => {
                      const profile = profileMap.get(member.user_id);
                      return <div key={member.user_id} className="flex items-center gap-3 rounded-xl bg-[#F6F1E8] px-3 py-3"><div className="flex h-8 w-8 items-center justify-center rounded-full bg-[#DDE5DC] text-xs font-bold text-[#355447]">{(profile?.display_name || "?").slice(0, 1).toUpperCase()}</div><div><div className="text-sm font-semibold">{profile?.display_name || "參與者"}</div><div className="mt-0.5 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8A8F86]">{member.role}</div></div></div>;
                    })}
                  </div>
                </section>

                <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm">
                  <div className="flex items-center gap-2"><History size={18} className="text-[#A64E3C]" /><h2 className="font-serif text-xl font-semibold">名稱變更紀錄</h2></div>
                  {history.length === 0 ? <p className="mt-4 text-sm text-[#68746B]">尚未更名。</p> : <div className="mt-4 space-y-4">{history.map((item) => <div key={item.id} className="border-l-2 border-[#E0D9CE] pl-4"><div className="text-sm"><span className="text-[#77776F]">{displayName(item.old_name)}</span><span className="mx-2">→</span><span className="font-semibold text-[#30463D]">{displayName(item.new_name)}</span></div><div className="mt-1 flex items-center gap-1.5 text-[10px] text-[#8A8F86]"><Clock3 size={11} />{new Date(item.changed_at).toLocaleString()}</div></div>)}</div>}
                </section>
              </aside>
            </div>
          </>
        ) : null}
      </main>
    </div>
  );
}
