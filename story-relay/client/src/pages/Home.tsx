/* Story Relay / 紙上接力：故事長頁＋側邊工作台；印刷朱紅只標記當前接力狀態，避免競賽式視覺。 */
import { useMemo, useState } from "react";
import { toast } from "sonner";
import {
  ArrowRight,
  BookOpen,
  Check,
  ChevronDown,
  Clock3,
  Feather,
  Info,
  Menu,
  MoreHorizontal,
  PenLine,
  Send,
  Sparkles,
  Users,
  X,
} from "lucide-react";

const members = [
  { name: "Alice", initials: "AL", status: "done", color: "#6B8F71", written: 1, weight: 2 },
  { name: "Ben", initials: "BE", status: "waiting", color: "#C39362", written: 0, weight: 4 },
  { name: "Carol", initials: "CA", status: "writing", color: "#D85C45", written: 1, weight: 1 },
  { name: "David", initials: "DA", status: "waiting", color: "#7A8793", written: 0, weight: 5 },
  { name: "Emma", initials: "EM", status: "waiting", color: "#967A9D", written: 0, weight: 3 },
];

const seedSegments = [
  { no: "00", author: "Writer 0", date: "故事種子", title: "一個沒有地圖的下午", text: "下午四點十七分，校舍後方的鐘突然停了。沒有人知道那一刻發生了什麼，只知道風把一張陌生的紙條，送到了五個人中間。" },
  { no: "01", author: "Alice", date: "今天 14:12", title: "紙條上的第一句話", text: "紙條上只有一句話：不要讓紅色的門在日落前打開。Alice 抬頭看向走廊盡頭，那裡明明只有一面斑駁的白牆，卻在牆角露出了一小截紅色。" },
  { no: "02", author: "Ben", date: "今天 14:26", title: "走廊盡頭", text: "他們五個人沒有立刻靠近。Ben 先把紙條翻到背面，發現上面印著一個很小的圓形圖案，像是有人用紅筆圈住了某個尚未發生的答案。" },
];

export default function Home() {
  const [activeTab, setActiveTab] = useState<"story" | "activity">("story");
  const [volunteered, setVolunteered] = useState(false);
  const [nominated, setNominated] = useState<string[]>([]);
  const [composerOpen, setComposerOpen] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [draft, setDraft] = useState("");

  const progress = submitted ? 4 : 3;
  const progressPercent = Math.round((progress / 10) * 100);
  const selectedNames = useMemo(() => nominated.join("、"), [nominated]);

  const toggleNomination = (name: string) => {
    setNominated((current) => current.includes(name) ? current.filter((item) => item !== name) : [...current, name]);
  };

  const handleSubmit = () => {
    if (draft.trim().length < 20) {
      toast.error("再多寫一點，讓下一棒有足夠的線索。", { description: "至少需要 20 個字。" });
      return;
    }
    setSubmitted(true);
    setComposerOpen(false);
    toast.success("段落已接上故事。", { description: "下一棒正在等待被選出。" });
  };

  return (
    <div className="min-h-screen bg-[#F5F1E9] text-[#1F2E2A]">
      <header className="sticky top-0 z-30 border-b border-[#D8D2C6] bg-[#F8F5EF]/95 backdrop-blur-md">
        <div className="mx-auto flex h-[72px] max-w-[1400px] items-center justify-between px-5 sm:px-8">
          <div className="flex items-center gap-3">
            <div className="relative flex h-10 w-10 items-center justify-center rounded-[12px] bg-[#233B35] shadow-[3px_3px_0_#D85C45]">
              <div className="h-5 w-4 rotate-[-8deg] rounded-[3px] border-2 border-[#F8F5EF]" />
              <div className="absolute h-5 w-4 translate-x-2 translate-y-1 rotate-[10deg] rounded-[3px] border-2 border-[#D85C45] bg-[#233B35]" />
            </div>
            <div className="leading-none">
              <div className="font-serif text-[20px] font-bold tracking-[-0.04em]">Story Relay</div>
              <div className="mt-1 font-mono text-[9px] uppercase tracking-[0.22em] text-[#8A8F86]">共同寫下下一段</div>
            </div>
          </div>
          <div className="hidden items-center gap-7 text-[13px] font-medium text-[#69736B] md:flex">
            <button className="border-b-2 border-[#D85C45] pb-1 text-[#233B35]">我的活動</button>
            <button onClick={() => toast("活動建立功能即將推出。")}>加入活動</button>
            <button onClick={() => toast("設定功能即將推出。")}>設定</button>
          </div>
          <div className="flex items-center gap-2">
            <button aria-label="更多選項" onClick={() => setMenuOpen(!menuOpen)} className="rounded-full p-2 text-[#69736B] transition hover:bg-[#ECE6DA]"><MoreHorizontal size={19} /></button>
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#D7DDD1] text-[11px] font-bold text-[#355447]">AL</div>
            {menuOpen && <div className="absolute right-5 top-[62px] w-44 rounded-xl border border-[#D8D2C6] bg-[#FFFDF8] p-2 text-sm shadow-xl"><button className="w-full rounded-lg px-3 py-2 text-left hover:bg-[#F3EEE5]" onClick={() => toast("分享連結已複製。")}>複製活動連結</button><button className="w-full rounded-lg px-3 py-2 text-left hover:bg-[#F3EEE5]" onClick={() => toast("這個功能即將推出。")}>離開活動</button></div>}
          </div>
        </div>
      </header>

      <main className="paper-grain mx-auto max-w-[1400px] px-5 py-8 sm:px-8 lg:py-12">
        <div className="mb-9 flex flex-col justify-between gap-5 border-b border-[#D8D2C6] pb-8 lg:flex-row lg:items-end">
          <div>
            <div className="mb-3 flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.18em] text-[#A06B59]"><span className="h-1.5 w-1.5 rounded-full bg-[#D85C45]" /> 進行中的活動 · SR-2048</div>
            <h1 className="font-serif text-[clamp(38px,5vw,68px)] font-semibold leading-[0.94] tracking-[-0.055em] text-[#233B35]">一個沒有地圖的下午</h1>
            <p className="mt-5 max-w-[640px] text-[15px] leading-7 text-[#68746B]">五個人，一張紙條，還有一扇不該在日落前打開的紅色門。</p><div className="mt-6 flex items-center gap-3 text-[11px] font-mono uppercase tracking-[0.12em] text-[#9A9B93]"><span className="editorial-underline text-[#A64E3C]">第 04 段等待接上</span><span>／</span><span>共 05 位作者</span></div>
          </div>
          <div className="flex items-center gap-3 text-sm text-[#68746B] lg:pb-1"><Clock3 size={16} className="text-[#A06B59]" /> 本輪剩餘 <strong className="font-mono text-[#233B35]">18:42</strong></div>
        </div>

        <div className="grid items-start gap-12 lg:grid-cols-[minmax(0,1fr)_360px] xl:gap-20">
          <section className="min-w-0">
            <div className="mb-8 flex items-center gap-1 border-b border-[#D8D2C6]">
              <button onClick={() => setActiveTab("story")} className={`relative px-1 pb-3 pr-6 text-sm font-semibold ${activeTab === "story" ? "text-[#233B35]" : "text-[#9A9B93]"}`}>故事內容 {activeTab === "story" && <span className="absolute bottom-[-1px] left-0 h-[2px] w-12 bg-[#D85C45]" />}</button>
              <button onClick={() => setActiveTab("activity")} className={`relative px-1 pb-3 text-sm font-semibold ${activeTab === "activity" ? "text-[#233B35]" : "text-[#9A9B93]"}`}>活動說明 {activeTab === "activity" && <span className="absolute bottom-[-1px] left-0 h-[2px] w-12 bg-[#D85C45]" />}</button>
            </div>
            {activeTab === "story" ? <div className="space-y-9">{seedSegments.map((segment, index) => <article key={segment.no} className="relay-node group relative pl-14 sm:pl-20"><div className="absolute left-0 top-1 font-mono text-[11px] tracking-[0.18em] text-[#A6A89F]">{segment.no}</div><div className="absolute left-[30px] top-2 hidden h-full border-l border-dashed border-[#C8C3B8] sm:block" />{index < seedSegments.length - 1 && <div className="absolute left-[26px] top-[27px] h-2 w-2 rounded-full bg-[#C6C8BD] sm:block" />}<div className="mb-3 flex flex-wrap items-center gap-2 text-[11px] font-mono uppercase tracking-[0.08em] text-[#9A9B93]"><span className="font-semibold text-[#A06B59]">{segment.author}</span><span>·</span><span>{segment.date}</span></div><h2 className="mb-4 font-serif text-[26px] font-semibold tracking-[-0.035em] text-[#30463D] sm:text-[31px]">{segment.title}</h2><p className="max-w-[720px] font-serif text-[18px] leading-[1.85] text-[#536159] sm:text-[19px]">{segment.text}</p></article>)}{submitted && <article className="animate-in slide-in-from-bottom-2 relative pl-14 duration-300 sm:pl-20"><div className="absolute left-0 top-1 font-mono text-[11px] tracking-[0.18em] text-[#D85C45]">03</div><div className="absolute left-[30px] top-2 hidden h-full border-l border-dashed border-[#D85C45]/50 sm:block" /><div className="mb-3 flex flex-wrap items-center gap-2 text-[11px] font-mono uppercase tracking-[0.08em] text-[#A06B59]"><span className="font-semibold">Alice</span><span>·</span><span>剛剛提交</span></div><h2 className="mb-4 font-serif text-[26px] font-semibold tracking-[-0.035em] text-[#30463D]">紅色不是門的顏色</h2><p className="max-w-[720px] whitespace-pre-line font-serif text-[18px] leading-[1.85] text-[#536159] sm:text-[19px]">{draft}</p></article>}<button onClick={() => setComposerOpen(true)} className="ml-14 flex items-center gap-3 border-b border-[#D85C45] pb-1 font-serif text-[17px] font-semibold text-[#A64E3C] transition hover:gap-5 sm:ml-20"><PenLine size={17} />接著寫下去 <ArrowRight size={16} /></button></div> : <div className="max-w-[680px] space-y-6 rounded-2xl bg-[#EDE8DE] p-7 sm:p-10"><div className="flex items-center gap-3 text-[#A64E3C]"><Info size={18} /><span className="font-mono text-[11px] uppercase tracking-[0.16em]">活動規則</span></div><h2 className="font-serif text-3xl font-semibold text-[#30463D]">故事屬於整個小組。</h2><p className="text-[15px] leading-8 text-[#647067]">每位同學一次寫一段。提交前可以修改自己的草稿，但不能編輯已提交的段落。下一位作者會從候選人中被隨機選出，等待越久，下一次被選中的機率越高。</p><p className="text-[15px] leading-8 text-[#647067]">請把注意力留給故事，而不是誰寫得最多。這裡沒有積分、排名或徽章，只有一段接一段，直到故事完成。</p></div>}
          </section>

          <aside className="space-y-5 lg:sticky lg:top-[104px]">
            <div className="paper-sheet rounded-2xl border border-[#D8D2C6] p-5 sm:p-6">
              <div className="mb-5 flex items-start justify-between"><div><div className="mb-1 font-mono text-[10px] uppercase tracking-[0.18em] text-[#A06B59]">故事進度</div><div className="font-serif text-[26px] font-semibold text-[#30463D]">{progress} <span className="text-[#A6A89F]">/ 10 段</span></div></div><BookOpen size={20} className="text-[#758576]" /></div>
              <div className="mb-6 h-2 overflow-hidden rounded-full bg-[#E5E2D9]"><div className="h-full rounded-full bg-[#6B8F71] transition-all duration-500" style={{ width: `${progressPercent * 2}%` }} /></div>
              <div className="space-y-3">{members.map((member) => <div key={member.name} className="flex items-center gap-3"><div className="flex h-8 w-8 items-center justify-center rounded-full text-[10px] font-bold text-white" style={{ backgroundColor: member.color }}>{member.initials}</div><div className="flex-1"><div className="flex items-center justify-between"><span className="text-sm font-medium text-[#425148]">{member.name}</span>{member.status === "done" && <Check size={14} className="text-[#6B8F71]" />}{member.status === "writing" && <span className="flex items-center gap-1.5 text-[10px] font-semibold text-[#D85C45]"><span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#D85C45]" />正在寫</span>}</div><div className="mt-1 h-1 rounded-full bg-[#EFEBE2]"><div className="h-full rounded-full" style={{ width: `${member.written ? "100%" : "0%"}`, backgroundColor: member.color }} /></div></div></div>)}</div>
              <div className="mt-6 border-t border-[#E4DFD5] pt-5 text-xs text-[#8A9189]"><div className="mb-2 flex justify-between"><span>小組完成度</span><strong className="font-mono text-[#526259]">{progressPercent}%</strong></div><div className="flex justify-between"><span>剩餘段落</span><strong className="font-mono text-[#526259]">{10 - progress} 段</strong></div></div>
            </div>

            <div className="relative overflow-hidden rounded-2xl bg-[#233B35] p-6 text-[#F8F5EF] shadow-[0_14px_30px_rgba(35,59,53,0.16)]"><div className="absolute -right-8 -top-8 h-32 w-32 rounded-full border border-[#D85C45]/30" /><div className="absolute -right-2 -top-2 h-20 w-20 rounded-full border border-[#D85C45]/30" /><div className="relative"><div className="mb-2 flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.18em] text-[#DCA294]"><Sparkles size={13} /> 下一棒的懸念</div><h3 className="editorial-underline mb-3 font-serif text-[25px] font-semibold leading-tight">下一段，會落在誰的筆下？</h3><p className="mb-5 text-[13px] leading-6 text-[#C6D0C5]">目前作者 Carol 正在寫作。你可以登記，或提名你認為適合接續的人。</p><button onClick={() => { setVolunteered(!volunteered); toast(volunteered ? "已取消登記。" : "已登記成為下一棒候選人。", { description: volunteered ? "你仍然可以再次登記。" : "你的名字會留在抽選池裡。" }); }} className={`w-full rounded-xl px-4 py-3 text-sm font-bold transition active:scale-[0.98] ${volunteered ? "bg-[#F8F5EF] text-[#233B35]" : "bg-[#D85C45] text-white hover:bg-[#C9523C]"}`}>{volunteered ? <span className="flex items-center justify-center gap-2"><Check size={16} /> 已登記成為下一棒</span> : "我想接著寫"}</button></div></div>

            <div className="paper-sheet rounded-2xl border border-[#D8D2C6] bg-[#F0ECE3] p-5"><div className="mb-4 flex items-center justify-between"><div className="flex items-center gap-2 text-sm font-semibold text-[#425148]"><Users size={16} />提名下一位作者</div><span className="font-mono text-[10px] text-[#999D93]">可複選</span></div><p className="mb-4 text-xs leading-5 text-[#7B847B]">提名會影響候選池，但不會直接決定結果。</p><div className="flex flex-wrap gap-2">{members.filter((member) => member.name !== "Carol").map((member) => <button key={member.name} onClick={() => toggleNomination(member.name)} className={`rounded-full border px-3 py-2 text-xs font-medium transition ${nominated.includes(member.name) ? "border-[#D85C45] bg-[#D85C45] text-white" : "border-[#D5D0C5] bg-[#FFFDF8] text-[#667168] hover:border-[#A5B0A3]"}`}>{nominated.includes(member.name) && <Check size={12} className="mr-1 inline" />}{member.name}</button>)}</div>{nominated.length > 0 && <div className="mt-4 flex items-center justify-between border-t border-[#D8D2C6] pt-4"><span className="text-[11px] text-[#7B847B]">已選 {selectedNames}</span><button onClick={() => { setNominated([]); toast("已清除提名。"); }} aria-label="清除提名" className="text-[#A06B59]"><X size={14} /></button></div>}</div>
          </aside>
        </div>
      </main>

      {composerOpen && <div className="fixed inset-0 z-50 flex items-end justify-center bg-[#1D2D28]/35 p-0 backdrop-blur-sm sm:items-center sm:p-6"><div className="w-full max-w-2xl rounded-t-3xl bg-[#FFFDF8] p-6 shadow-2xl sm:rounded-3xl sm:p-8"><div className="mb-6 flex items-start justify-between"><div><div className="mb-2 font-mono text-[10px] uppercase tracking-[0.18em] text-[#A06B59]">第 04 段 · Alice 的草稿</div><h2 className="font-serif text-3xl font-semibold text-[#30463D]">把下一句交給你</h2></div><button onClick={() => setComposerOpen(false)} className="rounded-full p-2 text-[#7C857C] hover:bg-[#F0ECE3]"><X size={20} /></button></div><textarea autoFocus value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="故事接著發生了……" className="min-h-[190px] w-full resize-none rounded-2xl border border-[#D8D2C6] bg-[#F7F3EB] p-5 font-serif text-[17px] leading-8 text-[#3D4E45] outline-none transition placeholder:text-[#AFB2A9] focus:border-[#A7B29F] focus:ring-4 focus:ring-[#DDE5D7]" /><div className="mt-4 flex items-center justify-between"><span className="font-mono text-[10px] text-[#9CA198]">{draft.length} 字 · 建議 100–300 字</span><button onClick={handleSubmit} className="flex items-center gap-2 rounded-xl bg-[#D85C45] px-5 py-3 text-sm font-bold text-white shadow-[3px_3px_0_#A94737] transition hover:bg-[#C9523C] active:translate-x-[1px] active:translate-y-[1px] active:shadow-none"><Send size={16} />提交這一段</button></div></div></div>}
    </div>
  );
}
