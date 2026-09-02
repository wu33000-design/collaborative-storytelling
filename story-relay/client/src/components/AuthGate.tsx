import type { ReactNode } from "react";
import { useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { LogOut } from "lucide-react";
import { supabase } from "@/lib/supabase";

function getRedirectUrl() {
  return new URL(import.meta.env.BASE_URL, window.location.origin).toString();
}

export default function AuthGate({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (!mounted) return;
      if (error) setAuthError(error.message);
      setUser(data.session?.user ?? null);
      setLoading(false);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      setLoading(false);
    });

    return () => {
      mounted = false;
      subscription.subscription.unsubscribe();
    };
  }, []);

  const signInWithGoogle = async () => {
    setAuthError(null);
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: getRedirectUrl(),
      },
    });

    if (error) setAuthError(error.message);
  };

  const signOut = async () => {
    setAuthError(null);
    const { error } = await supabase.auth.signOut();
    if (error) setAuthError(error.message);
  };

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] text-[#355447]">
        <p className="font-serif text-lg">正在確認登入狀態…</p>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[#F5F1E9] px-5 text-[#1F2E2A]">
        <main className="w-full max-w-md rounded-3xl border border-[#D8D2C6] bg-[#FFFDF8] p-8 shadow-sm sm:p-10">
          <div className="mb-8 flex items-center gap-3">
            <div className="relative flex h-11 w-11 items-center justify-center rounded-[12px] bg-[#233B35] shadow-[3px_3px_0_#D85C45]">
              <div className="h-5 w-4 rotate-[-8deg] rounded-[3px] border-2 border-[#F8F5EF]" />
              <div className="absolute h-5 w-4 translate-x-2 translate-y-1 rotate-[10deg] rounded-[3px] border-2 border-[#D85C45] bg-[#233B35]" />
            </div>
            <div>
              <div className="font-serif text-2xl font-bold tracking-[-0.04em]">Story Relay</div>
              <div className="mt-1 font-mono text-[10px] uppercase tracking-[0.18em] text-[#8A8F86]">共同寫下下一段</div>
            </div>
          </div>

          <h1 className="font-serif text-3xl font-semibold tracking-[-0.04em] text-[#233B35]">登入後開始接力</h1>
          <p className="mt-4 text-sm leading-7 text-[#68746B]">
            使用 Google 帳號登入。Story Relay 只要求基本的帳號、Email 與個人資料權限。
          </p>

          <button
            type="button"
            onClick={signInWithGoogle}
            className="mt-8 flex w-full items-center justify-center rounded-xl bg-[#233B35] px-5 py-3 text-sm font-semibold text-[#FFFDF8] transition hover:bg-[#304D44]"
          >
            使用 Google 登入
          </button>

          {authError && (
            <p className="mt-4 rounded-lg bg-[#F7E5DF] px-4 py-3 text-sm text-[#9B4637]">{authError}</p>
          )}
        </main>
      </div>
    );
  }

  return (
    <>
      {children}
      <button
        type="button"
        onClick={signOut}
        title="登出"
        aria-label="登出"
        className="fixed bottom-5 right-5 z-50 flex h-10 w-10 items-center justify-center rounded-full border border-[#D8D2C6] bg-[#FFFDF8] text-[#68746B] shadow-md transition hover:bg-[#ECE6DA]"
      >
        <LogOut size={17} />
      </button>
      {authError && (
        <div className="fixed bottom-5 left-5 z-50 max-w-sm rounded-lg bg-[#F7E5DF] px-4 py-3 text-sm text-[#9B4637] shadow-md">
          {authError}
        </div>
      )}
    </>
  );
}
