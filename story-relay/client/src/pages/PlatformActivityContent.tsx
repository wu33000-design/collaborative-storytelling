import { BookOpen, Loader2, RefreshCw, ShieldCheck, Users } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useRoute } from "wouter";
import { supabase } from "@/lib/supabase";

type Segment = {
  id: string;
  sequence_no: number;
  author_id: string | null;
  author_name: string | null;
  author_email: string | null;
  content: string;
  character_count: number;
  submitted_at: string;
};

type Round = {
  id: string;
  round_no: number;
  current_writer_id: string;
  current_writer_name: string | null;
  status: string;
  started_at: string;
  completed_at: string | null;
};

type Story = {
  id: string;
  title: string | null;
  prompt: string | null;
  status: string;
  required_segments: number | null;
  completed_at: string | null;
  segments: Segment[];
  rounds: Round[];
};

type Member = {
  user_id: string;
  display_name: string | null;
  email: string | null;
  role: string;
  joined_at: string;
  left_at: string | null;
};

type Group = {
  id: string;
  name: string;
  created_at: string;
  members: Member[];
  stories: Story[];
};

type ActivityContent = {
  activity: {
    id: string;
    code: string;
    name: string | null;
    prompt: string | null;
    initial_text: string | null;
    status: string;
    group_size: number | null;
    time_limit_seconds: number | null;
    min_words: number | null;
    max_words: number | null;
    required_segments: number | null;
    deadline: string | null;
    created_at: string;
    deleted_at: string | null;
    purge_after: string | null;
    host_user_id: string;
    host_name: string | null;
    host_email: string | null;
  };
  groups: Group[];
};

const formatDate = (value: string | null) => (value ? new Date(value).toLocaleString() : "—");
const statusLabel = (value: string) => value === "active" ? "進行中" : value === "closed" ? "已停止" : value;

export default function PlatformActivityContent() {
  const [, params] = useRoute("/admin/activity/:activityId/content");
  const activityId = params?.activityId;
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [content, setContent] = useState<ActivityContent | null>(null);

  const load = useCallback(async () => {
    if (!activityId) {
      setError("找不到活動 ID。");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    const { data, error: rpcError } = await supabase.rpc("get_platform_activity_content", { p_activity_id: activityId });
    if (rpcError) {
      setError(rpcError.message);
      setContent(null);
    } else {
      setContent(data as ActivityContent);
    }
    setLoading(false);
  }, [activityId]);

  useEffect(() => { void load(); }, [load]);

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-10 text-[#1F2E2A] sm:py-14">
      <main className="mx-auto max-w-6xl">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <Link href="/admin" className="text-sm text-[#68746B] hover:text-[#233B35]">← 回平台控制台</Link>
          <button type="button" onClick={() => void load()} disabled={loading} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-xs text-[#68746B] hover:bg-[#E9E3D8] disabled:opacity-50"><RefreshCw size={14}/>重新整理</button>
        </div>

        <header className="mt-8 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-9">
          <div className="flex items-center gap-2 text-[#A64E3C]"><ShieldCheck size={18}/><span className="font-mono text-[10px] uppercase tracking-[0.16em]">Platform administrator read-only view</span></div>
          <h1 className="mt-3 font-serif text-4xl font-semibold">活動內容檢視</h1>
          <p className="mt-4 text-sm leading-7 text-[#68746B]">此頁只有平台管理者可以開啟。檢視不會加入小組、不會改變參與統計，也不能從此頁投稿或操作接力。</p>
        </header>

        {loading && <div className="mt-6 flex items-center gap-2 rounded-2xl bg-[#FFFDF8] p-6 text-sm text-[#68746B]"><Loader2 size={17} className="animate-spin"/>載入活動內容中…</div>}
        {error && <div className="mt-6 rounded-2xl border border-[#E7C8BF] bg-[#F7E5DF] p-5 text-sm text-[#8D4033]"><div className="font-semibold">讀取失敗</div><div className="mt-2 break-words font-mono text-xs">{error}</div></div>}

        {!loading && content && <>
          <section className="mt-6 rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm sm:p-8">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div><div className="font-mono text-xs tracking-[0.08em] text-[#A06B59]">{content.activity.code}</div><h2 className="mt-2 font-serif text-3xl font-semibold">{content.activity.name || "未命名活動"}</h2></div>
              <div className="flex flex-wrap gap-2"><span className="rounded-full bg-[#E7EFE5] px-3 py-1 text-xs font-semibold text-[#456348]">{statusLabel(content.activity.status)}</span>{content.activity.deleted_at && <span className="rounded-full bg-[#F7E5DF] px-3 py-1 text-xs font-semibold text-[#8D4033]">回收桶</span>}</div>
            </div>
            <div className="mt-5 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <div><div className="text-xs text-[#7C827B]">主持人</div><div className="mt-1 font-semibold">{content.activity.host_name || "未命名帳號"}</div><div className="font-mono text-[10px] text-[#7C827B]">{content.activity.host_email || "尚未同步 Email"}</div></div>
              <div><div className="text-xs text-[#7C827B]">建立時間</div><div className="mt-1">{formatDate(content.activity.created_at)}</div></div>
              <div><div className="text-xs text-[#7C827B]">截止時間</div><div className="mt-1">{formatDate(content.activity.deadline)}</div></div>
              <div><div className="text-xs text-[#7C827B]">小組數</div><div className="mt-1">{content.groups.length}</div></div>
            </div>
            {content.activity.prompt && <div className="mt-6 rounded-2xl bg-[#F6F1E8] p-5"><div className="text-xs font-semibold text-[#68746B]">故事提示</div><p className="mt-2 whitespace-pre-wrap leading-7">{content.activity.prompt}</p></div>}
            {content.activity.initial_text && <div className="mt-4 rounded-2xl bg-[#F6F1E8] p-5"><div className="text-xs font-semibold text-[#68746B]">Writer 0 初始文字</div><p className="mt-2 whitespace-pre-wrap leading-7">{content.activity.initial_text}</p></div>}
          </section>

          <section className="mt-6 space-y-5">
            {content.groups.length === 0 && <div className="rounded-2xl bg-[#FFFDF8] p-6 text-sm text-[#68746B]">這個活動目前沒有小組。</div>}
            {content.groups.map((group) => <article key={group.id} className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-6 shadow-sm sm:p-8">
              <div className="flex flex-wrap items-center justify-between gap-3"><div className="flex items-center gap-2"><Users size={18}/><h3 className="font-serif text-2xl font-semibold">{group.name}</h3></div><div className="text-xs text-[#7C827B]">{group.members.filter(member => !member.left_at).length} 位目前成員</div></div>

              <div className="mt-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {group.members.map(member => <div key={`${group.id}-${member.user_id}-${member.joined_at}`} className="rounded-xl bg-[#F6F1E8] p-3 text-sm"><div className="font-semibold">{member.display_name || "未命名成員"}{member.left_at ? "（已離開）" : ""}</div><div className="mt-1 font-mono text-[10px] text-[#7C827B]">{member.email || member.user_id}</div></div>)}
              </div>

              <div className="mt-6 space-y-5">
                {group.stories.map(story => <section key={story.id} className="rounded-2xl border border-[#E3DDD2] p-5">
                  <div className="flex flex-wrap items-center justify-between gap-3"><div className="flex items-center gap-2"><BookOpen size={17}/><h4 className="font-serif text-xl font-semibold">{story.title || "未命名故事"}</h4></div><div className="text-xs text-[#68746B]">{statusLabel(story.status)} · {story.segments.length} 段</div></div>
                  {story.prompt && story.prompt !== content.activity.prompt && <p className="mt-4 whitespace-pre-wrap rounded-xl bg-[#F6F1E8] p-4 text-sm leading-7">{story.prompt}</p>}

                  <div className="mt-5 space-y-3">
                    {story.segments.length === 0 && <div className="text-sm text-[#7C827B]">尚無故事內容。</div>}
                    {story.segments.map(segment => <div key={segment.id} className="rounded-xl bg-[#FAF7F1] p-4">
                      <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-[#7C827B]"><span>#{segment.sequence_no} · {segment.author_id ? (segment.author_name || segment.author_email || "未命名作者") : "Writer 0"}</span><span>{formatDate(segment.submitted_at)}</span></div>
                      <p className="mt-3 whitespace-pre-wrap leading-7">{segment.content}</p>
                    </div>)}
                  </div>

                  {story.rounds.length > 0 && <details className="mt-5 rounded-xl border border-[#E3DDD2] p-4"><summary className="cursor-pointer text-sm font-semibold">接力輪次紀錄（{story.rounds.length}）</summary><div className="mt-3 space-y-2">{story.rounds.map(round => <div key={round.id} className="flex flex-wrap justify-between gap-2 rounded-lg bg-[#F6F1E8] px-3 py-2 text-xs"><span>Round {round.round_no} · {round.current_writer_name || round.current_writer_id}</span><span>{round.status} · {formatDate(round.started_at)}</span></div>)}</div></details>}
                </section>)}
              </div>
            </article>)}
          </section>
        </>}
      </main>
    </div>
  );
}
