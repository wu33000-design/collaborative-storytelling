import { FormEvent, useEffect, useState } from "react";
import { ArrowRight, Loader2, PenTool, ShieldCheck, Users } from "lucide-react";
import { Link, useLocation } from "wouter";
import { supabase } from "@/lib/supabase";

export default function Start() {
  const [isPlatformAdmin, setIsPlatformAdmin] = useState(false);
  const [code, setCode] = useState("");
  const [joining, setJoining] = useState(false);
  const [joinError, setJoinError] = useState<string | null>(null);
  const [, setLocation] = useLocation();

  useEffect(() => {
    let active = true;
    void supabase.rpc("is_platform_admin").then(({ data }) => {
      if (active) setIsPlatformAdmin(Boolean(data));
    });
    return () => {
      active = false;
    };
  }, []);

  const handleJoin = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const normalizedCode = code.trim();
    if (!normalizedCode) {
      setJoinError("請輸入活動代碼。");
      return;
    }

    setJoining(true);
    setJoinError(null);
    const { data, error } = await supabase.rpc("join_activity_by_code", { p_code: normalizedCode });

    if (error) {
      setJoinError(error.message);
      setJoining(false);
      return;
    }
    if (typeof data !== "string" || !data) {
      setJoinError("後端沒有回傳小組資料，請稍後再試。");
      setJoining(false);
      return;
    }

    setLocation(`/room/${data}`);
  };

  return (
    <div className="min-h-screen bg-[#F5F1E9] px-5 py-12 text-[#1F2E2A] sm:py-20">
      <main className="mx-auto max-w-3xl">
        <div className="mb-12 flex items-center gap-3">
          <div className="relative flex h-11 w-11 items-center justify-center rounded-[12px] bg-[#233B35] shadow-[3px_3px_0_#D85C45]">
            <div className="h-5 w-4 rotate-[-8deg] rounded-[3px] border-2 border-[#F8F5EF]" />
            <div className="absolute h-5 w-4 translate-x-2 translate-y-1 rotate-[10deg] rounded-[3px] border-2 border-[#D85C45] bg-[#233B35]" />
          </div>
          <div>
            <div className="font-serif text-2xl font-bold tracking-[-0.04em]">Story Relay</div>
            <div className="mt-1 font-mono text-[10px] uppercase tracking-[0.18em] text-[#8A8F86]">共同寫下下一段</div>
          </div>
        </div>

        <h1 className="max-w-2xl font-serif text-5xl font-semibold leading-[0.98] tracking-[-0.055em] text-[#233B35] sm:text-6xl">你今天想怎麼參與？</h1>
        <p className="mt-5 max-w-xl text-sm leading-7 text-[#68746B]">同一個帳號可以在不同活動中扮演不同角色，不需要預先被標記成主持人或參與者。</p>

        <div className="mt-10 grid gap-5 md:grid-cols-2">
          <Link href="/create" className="group rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
            <div className="flex h-11 w-11 items-center justify-center rounded-full bg-[#E8E2D7] text-[#355447]"><PenTool size={20} /></div>
            <h2 className="mt-6 font-serif text-3xl font-semibold tracking-[-0.04em] text-[#233B35]">建立／管理活動</h2>
            <p className="mt-3 text-sm leading-7 text-[#68746B]">建立活動後，你就是該活動的主持人。所有設定都可以留白，不設限。</p>
            <span className="mt-6 inline-flex items-center gap-2 text-sm font-semibold text-[#A64E3C]">前往主持人區 <ArrowRight size={16} className="transition group-hover:translate-x-1" /></span>
          </Link>

          <section className="rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-7 shadow-sm">
            <div className="flex h-11 w-11 items-center justify-center rounded-full bg-[#E8E2D7] text-[#355447]"><Users size={20} /></div>
            <h2 className="mt-6 font-serif text-3xl font-semibold tracking-[-0.04em] text-[#233B35]">加入活動</h2>
            <p className="mt-3 text-sm leading-7 text-[#68746B]">直接輸入主持人提供的活動代碼。加入成功後會進入你的小組故事房間。</p>

            <form className="mt-5" onSubmit={handleJoin}>
              <label htmlFor="activity-code" className="mb-2 block text-xs font-semibold uppercase tracking-[0.12em] text-[#69736B]">活動代碼</label>
              <div className="flex gap-2">
                <input id="activity-code" value={code} onChange={(event) => setCode(event.target.value)} placeholder="例如 SR-2048" autoComplete="off" disabled={joining} className="min-w-0 flex-1 rounded-xl border border-[#CFC8BB] bg-white px-3 py-2.5 font-mono text-sm uppercase tracking-[0.08em] outline-none transition focus:border-[#355447] focus:ring-2 focus:ring-[#355447]/15 disabled:opacity-60" />
                <button type="submit" disabled={joining} className="flex shrink-0 items-center justify-center gap-1.5 rounded-xl bg-[#233B35] px-4 py-2.5 text-sm font-semibold text-[#FFFDF8] transition hover:bg-[#304D44] disabled:opacity-60">
                  {joining ? <Loader2 size={16} className="animate-spin" /> : <ArrowRight size={16} />}{joining ? "加入中" : "加入"}
                </button>
              </div>
            </form>
            {joinError && <div className="mt-4 rounded-xl border border-[#E7C8BF] bg-[#F7E5DF] px-4 py-3 text-xs leading-5 text-[#8D4033]">{joinError}</div>}
          </section>
        </div>

        {isPlatformAdmin && (
          <Link href="/admin" className="mt-5 flex items-center justify-between gap-5 rounded-2xl border border-[#C9D5CA] bg-[#E7EFE5] px-6 py-5 transition hover:-translate-y-0.5">
            <div className="flex items-center gap-4">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-[#355447] text-[#FFFDF8]"><ShieldCheck size={18} /></div>
              <div><div className="font-serif text-xl font-semibold text-[#233B35]">平台管理</div><div className="mt-1 text-xs text-[#68746B]">查看全站成員參與統計並匯出 CSV</div></div>
            </div>
            <ArrowRight size={17} className="text-[#355447]" />
          </Link>
        )}
      </main>
    </div>
  );
}
