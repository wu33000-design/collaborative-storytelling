import { useEffect, useRef, useState } from "react";

type Check = {
  label: string;
  payload: string;
  textMatches: boolean;
  scriptNodes: number;
  imgNodes: number;
};

const payloads = [
  { label: "Activity name", payload: '<script>window.__xssProbe=1</script>' },
  { label: "Prompt", payload: '<img src=x onerror="window.__xssProbe=1">' },
  { label: "Display name", payload: '" onmouseover="window.__xssProbe=1" &lt;tag&gt; &amp; \'quoted\'' },
  { label: "Segment", payload: '<svg onload="window.__xssProbe=1"></svg> & <b>bold?</b>' },
];

export default function XssSmokeProbe() {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const [checks, setChecks] = useState<Check[]>([]);
  const [sideEffect, setSideEffect] = useState(0);

  useEffect(() => {
    (window as Window & { __xssProbe?: number }).__xssProbe = 0;

    const timer = window.setTimeout(() => {
      const root = rootRef.current;
      if (!root) return;

      const results = payloads.map(({ label, payload }, index) => {
        const node = root.querySelector(`[data-xss-field="${index}"]`);
        return {
          label,
          payload,
          textMatches: node?.textContent === payload,
          scriptNodes: node?.querySelectorAll("script").length ?? 0,
          imgNodes: node?.querySelectorAll("img,svg").length ?? 0,
        };
      });

      setChecks(results);
      setSideEffect((window as Window & { __xssProbe?: number }).__xssProbe ?? 0);
    }, 100);

    return () => window.clearTimeout(timer);
  }, []);

  const complete = checks.length === payloads.length;
  const passed = complete && checks.every((item) => item.textMatches && item.scriptNodes === 0 && item.imgNodes === 0) && sideEffect === 0;

  return (
    <div className="min-h-screen bg-[#F5F1E9] p-6 text-[#1F2E2A]">
      <main className="mx-auto max-w-4xl rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-8 shadow-sm">
        <div className="font-mono text-xs uppercase tracking-[0.16em] text-[#A06B59]">Temporary Test Page</div>
        <h1 className="mt-3 font-serif text-3xl font-semibold text-[#233B35]">CLASSROOM_100 C3 XSS Smoke Probe</h1>
        <p className="mt-3 text-sm leading-6 text-[#68746B]">React JSX 文字渲染測試：活動名稱、prompt、display name、segment 應顯示為純文字，不建立可執行 HTML/JS 節點。</p>

        <div ref={rootRef} className="mt-7 grid gap-4">
          {payloads.map((item, index) => (
            <section key={item.label} className="rounded-2xl bg-[#F3EEE5] p-5">
              <div className="text-xs font-semibold uppercase tracking-[0.08em] text-[#7B756D]">{item.label}</div>
              <div data-xss-field={index} className="mt-2 break-all font-mono text-sm text-[#233B35]">{item.payload}</div>
            </section>
          ))}
        </div>

        <div className="mt-7 grid gap-3 sm:grid-cols-2">
          <Stat label="Fields checked" value={`${checks.length} / ${payloads.length}`} />
          <Stat label="Payload side effect" value={String(sideEffect)} />
          <Stat label="Unexpected script nodes" value={String(checks.reduce((sum, item) => sum + item.scriptNodes, 0))} />
          <Stat label="Unexpected img/svg nodes" value={String(checks.reduce((sum, item) => sum + item.imgNodes, 0))} />
        </div>

        {complete && (
          <div className={`mt-6 rounded-2xl p-5 font-semibold ${passed ? "bg-[#E7EFE5] text-[#355447]" : "bg-[#F7E5DF] text-[#8D4033]"}`}>
            {passed ? "PASS：4 類使用者輸入皆以純文字呈現，未建立可執行 HTML/JS 節點。" : "FAIL：至少一個欄位未被安全地當作純文字渲染。"}
          </div>
        )}
      </main>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl bg-[#F3EEE5] p-4"><div className="text-xs text-[#7B756D]">{label}</div><div className="mt-1 font-mono text-sm font-semibold text-[#233B35]">{value}</div></div>;
}
