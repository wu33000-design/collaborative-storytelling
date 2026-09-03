import { FormEvent, useState } from "react";
import { ArrowRight, KeyRound, Loader2 } from "lucide-react";
import { Link, useLocation } from "wouter";
import { supabase } from "@/lib/supabase";

export default function JoinActivity() {
  const [code, setCode] = useState("");
  const [joining, setJoining] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [, setLocation] = useLocation();

  const handleJoin = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    const normalizedCode = code.trim();
    if (!normalizedCode) {
      setError("請輸入活動代碼。");
      return;
    }

    setJoining(true);
    setError(null);

    const { data, error: rpcError } = await supabase.rpc("join_activity_by_code", {
      p_code: normalizedCode,
    });

    if (rpcError) {
      setError(rpcError.message);
      setJoining(false);
      return;
    }

    if (typeof data !== "string" || !data) {
      setError("後端沒有回傳小組資料，請稍後再試。");
      setJoining(false);
      return;
    }

    setLocation(`/room/${data}`);
  };

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-12 text-[#1F2E2A] sm:py-20">
      <main className="mx-auto max-w-xl">
        <Link href="/" className="mb-8 inline-flex text-sm text-[#68746B] hover:text-[#233B35]">← 回到入口</Link>
        <div className="mb-10 flex items-center gap-3">
          <div className="relative flex h-11 w-11 items-center justify-center rounded-[12px] bg-[#233B35] shadow-[3px_3px_0_#D85C45]">
            <div className="h-5 w-4 rotate-[-8deg] rounded-[3px] border-2 border-[#F8F5EF]" />
            <div className="absolute h-5 w-4 translate-x-2 translate-y-1 rotate-[10deg] rounded-[3px] border-2 border-[#D85C45] bg-[#233B35]" />
          </div>
          <div>
            <div className="font-serif text-2xl font-bold tracking-[-0.04em]">Story Relay</div>
            <div className="mt-1 font-mono text-[10px] uppercase tracking-[0.18em] text-[#8A8F86]">共同寫下下一段</div>
          </div>
        </div>

        <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm sm:p-10">
          <div className="mb-6 flex h-11 w-11 items-center justify-center rounded-full bg-[#E9E5DA] text-[#355447]"><KeyRound size={20} /></div>
          <h1 className="font-serif text-4xl font-semibold tracking-[-0.045em] text-[#233B35]">加入活動</h1>
          <p className="mt-4 text-sm leading-7 text-[#68746B]">輸入主持人提供的活動代碼。加入成功後會直接進入你的小組故事房間。</p>

          <form className="mt-8" onSubmit={handleJoin}>
            <label htmlFor="activity-code" className="mb-2 block text-xs font-semibold uppercase tracking-[0.12em] text-[#69736B]">活動代碼</label>
            <div className="flex flex-col gap-3 sm:flex-row">
              <input id="activity-code" value={code} onChange={(event) => setCode(event.target.value)} placeholder="例如 SR-2048" autoComplete="off" disabled={joining} className="min-w-0 flex-1 rounded-xl border border-[#CFC8BB] bg-white px-4 py-3 font-mono text-base uppercase tracking-[0.08em] outline-none transition focus:border-[#355447] focus:ring-2 focus:ring-[#355447]/15 disabled:opacity-60" />
              <button type="submit" disabled={joining} className="flex items-center justify-center gap-2 rounded-xl bg-[#233B35] px-5 py-3 text-sm font-semibold text-[#FFFDF8] transition hover:bg-[#304D44] disabled:cursor-not-allowed disabled:opacity-60">
                {joining ? <Loader2 size={17} className="animate-spin" /> : <ArrowRight size={17} />}{joining ? "加入中…" : "加入"}
              </button>
            </div>
          </form>

          {error && <div className="mt-5 rounded-xl border border-[#E7C8BF] bg-[#F7E5DF] px-4 py-3 text-sm leading-6 text-[#8D4033]"><div className="font-semibold">加入失敗</div><div className="mt-1 break-words font-mono text-xs">{error}</div></div>}
        </section>

        <Link href="/demo" className="mt-6 inline-flex text-sm text-[#68746B] underline decoration-[#B9B2A5] underline-offset-4 hover:text-[#233B35]">查看目前的靜態 Story Relay demo</Link>
      </main>
    </div>
  );
}
