import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { BookOpen, Check, Clock3, Hand, History, Loader2, PenLine, Play, RefreshCw, Send, Users } from "lucide-react";
import { Link, useRoute } from "wouter";
import { supabase } from "@/lib/supabase";

type Activity = {
  id: string;
  code: string;
  name: string | null;
  prompt: string | null;
  status: string;
  min_words: number | null;
  max_words: number | null;
  time_limit_seconds: number | null;
  deadline: string | null;
  closed_reason: string | null;
};
type Group = { id: string; name: string; activity_id: string };
type Story = { id: string; title: string | null; prompt: string | null; status: string };
type Segment = { id: string; sequence_no: number; author_id: string | null; content: string; submitted_at: string };
type Member = { user_id: string; role: string; joined_at: string };
type Profile = { id: string; display_name: string; avatar_url: string | null };
type NameHistory = { id: string; old_name: string | null; new_name: string | null; changed_at: string };
type RelayRound = { id: string; round_no: number; current_writer_id: string; status: string; started_at: string };
type Nomination = { candidate_id: string };
type Volunteer = { user_id: string };

const displayName = (value: string | null) => value || "未命名活動";
const storyStatusLabel = (value: string, closedReason: string | null) => closedReason === "deadline" ? "已截止" : value === "active" ? "進行中" : value === "completed" ? "已完成" : value === "closed" || value === "stopped" ? "已停止" : value;
const formatCountdown = (seconds: number) => {
  const safe = Math.max(0, seconds);
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  const secs = safe % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
    : `${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
};

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
  const [nominations, setNominations] = useState<Nomination[]>([]);
  const [volunteers, setVolunteers] = useState<Volunteer[]>([]);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [startingRound, setStartingRound] = useState(false);
  const [draft, setDraft] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [intentBusy, setIntentBusy] = useState<string | null>(null);
  const [roundRemainingSeconds, setRoundRemainingSeconds] = useState<number | null>(null);

  const profileMap = useMemo(() => new Map(profiles.map((profile) => [profile.id, profile])), [profiles]);
  const nominatedIds = useMemo(() => new Set(nominations.map((item) => item.candidate_id)), [nominations]);
  const volunteerIds = useMemo(() => new Set(volunteers.map((item) => item.user_id)), [volunteers]);

  const loadRoom = useCallback(async (silent = false) => {
    if (!groupId) {
      setError("找不到小組 ID。");
      setLoading(false);
      return;
    }

    if (!silent) setLoading(true);
    setError(null);

    const { data: sessionData } = await supabase.auth.getSession();
    setCurrentUserId(sessionData.session?.user.id ?? null);

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

    const { error: deadlineError } = await supabase.rpc("finalize_activity_deadline", { p_activity_id: loadedGroup.activity_id });
    if (deadlineError) {
      setError(deadlineError.message);
      setLoading(false);
      return;
    }

    const [activityResult, storyResult, memberResult, historyResult] = await Promise.all([
      supabase.from("activities").select("id, code, name, prompt, status, min_words, max_words, time_limit_seconds, deadline, closed_reason").eq("id", loadedGroup.activity_id).maybeSingle(),
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
      supabase.from("relay_rounds").select("id, round_no, current_writer_id, status, started_at").eq("story_id", loadedStory.id).in("status", ["open", "writing"]).order("round_no", { ascending: false }).limit(1).maybeSingle(),
    ]);

    if (segmentResult.error || profileResult.error || roundResult.error) {
      setError(segmentResult.error?.message || profileResult.error?.message || roundResult.error?.message || "讀取房間資料失敗。");
      setLoading(false);
      return;
    }

    const loadedRound = (roundResult.data as RelayRound | null) ?? null;
    setSegments((segmentResult.data ?? []) as Segment[]);
    setProfiles((profileResult.data ?? []) as Profile[]);
    setRound(loadedRound);

    if (loadedRound) {
      const [nominationResult, volunteerResult] = await Promise.all([
        supabase.from("nominations").select("candidate_id").eq("round_id", loadedRound.id),
        supabase.from("volunteers").select("user_id").eq("round_id", loadedRound.id),
      ]);
      if (nominationResult.error || volunteerResult.error) {
        setError(nominationResult.error?.message || volunteerResult.error?.message || "讀取下一棒意向失敗。");
      }
      setNominations((nominationResult.data ?? []) as Nomination[]);
      setVolunteers((volunteerResult.data ?? []) as Volunteer[]);
    } else {
      setNominations([]);
      setVolunteers([]);
    }

    setLoading(false);
  }, [groupId]);

  useEffect(() => {
    void loadRoom();
  }, [loadRoom]);

  useEffect(() => {
    if (!activity?.id || activity.status !== "active" || !activity.deadline) return;
    const deadlineMs = Date.parse(activity.deadline);
    if (!Number.isFinite(deadlineMs)) return;

    let timer: number | undefined;
    const finalize = async () => {
      const { error: deadlineError } = await supabase.rpc("finalize_activity_deadline", { p_activity_id: activity.id });
      if (deadlineError) setError(deadlineError.message);
      else await loadRoom(true);
    };

    const remaining = deadlineMs - Date.now();
    if (remaining <= 0) {
      void finalize();
      return;
    }

    timer = window.setTimeout(() => void finalize(), Math.min(remaining + 50, 2_147_000_000));
    return () => {
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [activity?.deadline, activity?.id, activity?.status, loadRoom]);

  useEffect(() => {
    const limitSeconds = activity?.time_limit_seconds;
    if (!round || story?.status !== "active" || !limitSeconds || limitSeconds <= 0) {
      setRoundRemainingSeconds(null);
      return;
    }

    const startedMs = Date.parse(round.started_at);
    if (!Number.isFinite(startedMs)) {
      setRoundRemainingSeconds(null);
      return;
    }

    const endsAt = startedMs + limitSeconds * 1000;
    const tick = () => setRoundRemainingSeconds(Math.max(0, Math.ceil((endsAt - Date.now()) / 1000)));
    tick();
    const interval = window.setInterval(tick, 1000);
    return () => window.clearInterval(interval);
  }, [activity?.time_limit_seconds, round, story?.status]);

  useEffect(() => {
    if (!groupId || !group || !activity || !story) return;

    const refresh = () => {
      void loadRoom(true);
    };

    const channel = supabase
      .channel(`story-room:${groupId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "segments", filter: `story_id=eq.${story.id}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "relay_rounds", filter: `story_id=eq.${story.id}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "stories", filter: `id=eq.${story.id}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "activities", filter: `id=eq.${activity.id}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "activity_name_history", filter: `activity_id=eq.${activity.id}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "group_members", filter: `group_id=eq.${groupId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "nominations", filter: `round_id=eq.${round?.id ?? "00000000-0000-0000-0000-000000000000"}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "volunteers", filter: `round_id=eq.${round?.id ?? "00000000-0000-0000-0000-000000000000"}` }, refresh)
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [activity, group, groupId, loadRoom, round?.id, story]);

  const handleStartRound = async () => {
    if (!groupId) return;
    setStartingRound(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc("start_relay_round", { p_group_id: groupId });
    if (rpcError) setError(rpcError.message);
    setStartingRound(false);
    await loadRoom();
  };

  const handleVolunteer = async () => {
    if (!round) return;
    setIntentBusy("volunteer");
    setError(null);
    const { error: rpcError } = await supabase.rpc("volunteer_for_round", { p_round_id: round.id });
    if (rpcError) setError(rpcError.message);
    setIntentBusy(null);
    await loadRoom(true);
  };

  const handleNominate = async (candidateId: string) => {
    if (!round) return;
    setIntentBusy(candidateId);
    setError(null);
    const { error: rpcError } = await supabase.rpc("nominate_candidate", {
      p_round_id: round.id,
      p_candidate_id: candidateId,
    });
    if (rpcError) setError(rpcError.message);
    setIntentBusy(null);
    await loadRoom(true);
  };

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!round || !draft.trim()) return;

    setSubmitting(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc("submit_segment", {
      p_round_id: round.id,
      p_content: draft.trim(),
    });

    if (rpcError) {
      setError(rpcError.message);
      setSubmitting(false);
      await loadRoom(true);
      return;
    }

    setDraft("");
    setSubmitting(false);
    await loadRoom();
  };

  if (loading) {
    return <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]"><Loader2 className="animate-spin" size={28} /></div>;
  }

  const currentWriter = round ? profileMap.get(round.current_writer_id) : null;
  const isCurrentWriter = Boolean(round && currentUserId && round.current_writer_id === currentUserId);
  const hasVolunteered = Boolean(currentUserId && volunteerIds.has(currentUserId));
  const draftLength = draft.trim().length;
  const belowMinimum = activity?.min_words != null && draftLength < activity.min_words;
  const aboveMaximum = activity?.max_words != null && draftLength > activity.max_words;
  const deadlineClosed = activity?.closed_reason === "deadline";
  const roundTimeExpired = roundRemainingSeconds === 0;
  const roundTimeImminent = roundRemainingSeconds != null && roundRemainingSeconds > 0 && roundRemainingSeconds <= 60;

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-5xl">
        <div className="flex items-center justify-between gap-4">
          <Link href="/" className="text-sm text-[#68746B] hover:text-[#233B35]">← 回到入口</Link>
          <button type="button" onClick={() => void loadRoom()} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B] hover:bg-[#E9E3D8]"><RefreshCw size={14} />重新整理</button>
        </div>

        {error && (
          <section className="mt-8 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-[#8D4033]">
            <div className="font-semibold">房間操作失敗</div>
            <div className="mt-2 break-words font-mono text-xs">{error}</div>
          </section>
        )}

        {activity && group && story ? (
          <>
            <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
              <div className="flex flex-wrap items-start justify-between gap-5">
                <div>
                  <div className="font-mono text-[10px] uppercase tracking-[0.16em] text-[#A06B59]">{activity.code} · {group.name}</div>
                  <h1 className="mt-3 font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35] sm:text-5xl">{displayName(activity.name)}</h1>
                  <p className="mt-4 max-w-2xl text-sm leading-7 text-[#68746B]">{activity.prompt || story.prompt || "老師沒有設定故事提示。"}</p>
                  {activity.deadline && <p className="mt-2 text-xs text-[#8A8F86]">截止時間：{new Date(activity.deadline).toLocaleString()}</p>}
                </div>
                <span className={`rounded-full px-3 py-1.5 text-xs font-semibold ${story.status === "active" ? "bg-[#E7EFE5] text-[#456348]" : deadlineClosed ? "bg-[#F5E6D8] text-[#8B5E37]" : "bg-[#ECE9E3] text-[#6F746F]"}`}>{storyStatusLabel(story.status, activity.closed_reason)}</span>
              </div>

              <div className="mt-6 rounded-2xl bg-[#F3EEE5] p-5">
                {round ? (
                  <div className="flex flex-wrap items-center justify-between gap-4">
                    <div>
                      <div className="font-mono text-[10px] uppercase tracking-[0.12em] text-[#A06B59]">Round {round.round_no} · {round.status}</div>
                      <div className="mt-1 text-sm text-[#34453E]">目前作者：<span className="font-semibold">{currentWriter?.display_name || "參與者"}</span></div>
                    </div>
                    {isCurrentWriter && <span className="rounded-full bg-[#DDE9DE] px-3 py-1 text-xs font-semibold text-[#355447]">輪到你了</span>}
                  </div>
                ) : story.status === "active" ? (
                  <div className="flex flex-wrap items-center justify-between gap-4">
                    <div><div className="font-semibold text-[#30463D]">接力尚未開始</div><div className="mt-1 text-xs leading-5 text-[#68746B]">開始後，後端會依目前 selection weight 抽出第一位作者。</div></div>
                    <button type="button" disabled={startingRound || activity.status !== "active"} onClick={() => void handleStartRound()} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-4 py-2.5 text-sm font-semibold text-[#FFFDF8] disabled:opacity-60">{startingRound ? <Loader2 size={15} className="animate-spin" /> : <Play size={15} />}開始第一輪</button>
                  </div>
                ) : story.status === "completed" ? (
                  <div><div className="font-semibold text-[#30463D]">故事已完成</div><div className="mt-1 text-xs text-[#68746B]">故事已封存為唯讀，不會再建立新的接力輪次。</div></div>
                ) : deadlineClosed ? (
                  <div><div className="font-semibold text-[#7C5635]">活動已截止</div><div className="mt-1 text-xs text-[#7B6A59]">截止時間已到；未完成的 Round 已標記為 expired，既有故事內容保留為唯讀。</div></div>
                ) : (
                  <div><div className="font-semibold text-[#30463D]">故事已停止</div><div className="mt-1 text-xs text-[#68746B]">主持人已停止活動；既有內容保留為唯讀，不會再建立新的接力輪次。</div></div>
                )}
              </div>
            </header>

            <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1.45fr)_minmax(280px,0.75fr)]">
              <div className="space-y-6">
                <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-8">
                  <div className="flex items-center gap-2"><BookOpen size={19} className="text-[#A64E3C]" /><h2 className="font-serif text-2xl font-semibold">{story.status === "active" ? "目前故事" : "完整故事"}</h2></div>
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

                {round && story.status === "active" && (
                  <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-8">
                    <div className="flex flex-wrap items-center justify-between gap-3">
                      <div className="flex items-center gap-2"><PenLine size={19} className="text-[#A64E3C]" /><h2 className="font-serif text-2xl font-semibold">下一段</h2></div>
                      {roundRemainingSeconds != null && (
                        <div className={`inline-flex items-center gap-2 rounded-xl px-3.5 py-2 ${roundTimeExpired || roundTimeImminent ? "bg-[#F7E5DF] text-[#8D4033]" : "bg-[#EDF3EC] text-[#355447]"}`}>
                          <Clock3 size={15} />
                          <span className="text-xs font-semibold">{roundTimeExpired ? "本輪時間已到" : "本輪剩餘"}</span>
                          {!roundTimeExpired && <span className="font-mono text-sm font-bold tabular-nums">{formatCountdown(roundRemainingSeconds)}</span>}
                        </div>
                      )}
                    </div>
                    {isCurrentWriter ? (
                      <form onSubmit={handleSubmit} className="mt-5">
                        <textarea
                          value={draft}
                          onChange={(event) => setDraft(event.target.value)}
                          rows={7}
                          disabled={submitting}
                          placeholder="接續故事，寫下你的這一段……"
                          className="w-full resize-y rounded-2xl border border-[#CFC8BB] bg-white px-4 py-4 text-[15px] leading-7 outline-none focus:border-[#355447] focus:ring-2 focus:ring-[#355447]/10 disabled:opacity-60"
                        />
                        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
                          <div className={`text-xs ${belowMinimum || aboveMaximum ? "text-[#9B4637]" : "text-[#7B827B]"}`}>
                            目前 {draftLength} 字元
                            {activity.min_words != null ? ` · 最少 ${activity.min_words}` : ""}
                            {activity.max_words != null ? ` · 最多 ${activity.max_words}` : ""}
                          </div>
                          <button type="submit" disabled={submitting || !draft.trim() || belowMinimum || aboveMaximum} className="inline-flex items-center gap-2 rounded-xl bg-[#233B35] px-5 py-2.5 text-sm font-semibold text-[#FFFDF8] disabled:cursor-not-allowed disabled:opacity-50">
                            {submitting ? <Loader2 size={15} className="animate-spin" /> : <Send size={15} />}
                            {submitting ? "提交中…" : "提交這一段"}
                          </button>
                        </div>
                        <p className="mt-3 text-xs leading-5 text-[#8A8F86]">{nominations.length > 0 ? `提交後只會從 ${nominations.length} 位提名者中依等待權重抽選下一棒。` : "目前沒有提名；提交後會從所有合資格同學中依等待權重抽選下一棒。"}</p>
                      </form>
                    ) : (
                      <div className="mt-5 rounded-2xl bg-[#F3EEE5] p-5 text-sm leading-7 text-[#68746B]">等待 <span className="font-semibold text-[#30463D]">{currentWriter?.display_name || "目前作者"}</span> 完成這一段。提交後系統會依提名候選池與最新等待權重選出下一位作者。</div>
                    )}
                  </section>
                )}
              </div>

              <aside className="space-y-6">
                <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm">
                  <div className="flex items-center gap-2"><Users size={18} className="text-[#355447]" /><h2 className="font-serif text-xl font-semibold">小組成員</h2></div>
                  {round && story.status === "active" && <p className="mt-2 text-xs leading-5 text-[#7B827B]">在自己的名字旁登記想接下一棒；目前作者可在其他成員旁提名候選人。</p>}
                  <div className="mt-4 space-y-3">
                    {members.map((member) => {
                      const profile = profileMap.get(member.user_id);
                      const selected = round?.current_writer_id === member.user_id;
                      const volunteered = volunteerIds.has(member.user_id);
                      const nominated = nominatedIds.has(member.user_id);
                      const isSelf = currentUserId === member.user_id;
                      const canVolunteer = Boolean(round && story.status === "active" && isSelf && member.role === "student" && !isCurrentWriter);
                      const canNominate = Boolean(round && story.status === "active" && isCurrentWriter && !isSelf && member.role === "student");

                      return (
                        <div key={member.user_id} className={`flex items-center gap-3 rounded-xl px-3 py-3 ${selected ? "bg-[#E7EFE5]" : "bg-[#F6F1E8]"}`}>
                          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#DDE5DC] text-xs font-bold text-[#355447]">{(profile?.display_name || "?").slice(0, 1).toUpperCase()}</div>
                          <div className="min-w-0 flex-1">
                            <div className="text-sm font-semibold">{profile?.display_name || "參與者"}{isSelf ? <span className="ml-1 text-[10px] font-normal text-[#8A8F86]">（你）</span> : null}</div>
                            <div className="mt-0.5 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8A8F86]">{member.role}{selected ? " · current writer" : ""}{volunteered ? " · volunteer" : ""}{nominated ? " · nominated" : ""}</div>
                          </div>

                          {round && story.status === "active" && isSelf && member.role === "student" && (
                            <button
                              type="button"
                              disabled={!canVolunteer || hasVolunteered || intentBusy === "volunteer"}
                              onClick={() => void handleVolunteer()}
                              className={`inline-flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-2 text-xs font-semibold transition ${hasVolunteered ? "bg-[#DDE9DE] text-[#355447]" : "bg-[#355447] text-[#FFFDF8] hover:bg-[#426558]"} disabled:cursor-not-allowed disabled:opacity-55`}
                              title={isCurrentWriter ? "目前作者不能登記成為自己的下一棒" : "登記想接下一棒"}
                            >
                              {intentBusy === "volunteer" ? <Loader2 size={13} className="animate-spin" /> : hasVolunteered ? <Check size={13} /> : <Hand size={13} />}
                              {hasVolunteered ? "已登記" : "登記"}
                            </button>
                          )}

                          {canNominate && (
                            <button
                              type="button"
                              disabled={nominated || intentBusy === member.user_id}
                              onClick={() => void handleNominate(member.user_id)}
                              className={`inline-flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-2 text-xs font-semibold transition ${nominated ? "bg-[#F1DCD5] text-[#8D4033]" : "bg-[#A64E3C] text-[#FFFDF8] hover:bg-[#8D4033]"} disabled:cursor-not-allowed disabled:opacity-65`}
                            >
                              {intentBusy === member.user_id ? <Loader2 size={13} className="animate-spin" /> : nominated ? <Check size={13} /> : null}
                              {nominated ? "已提名" : "提名"}
                            </button>
                          )}
                        </div>
                      );
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
