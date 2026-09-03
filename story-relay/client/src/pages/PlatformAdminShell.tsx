import { useEffect, useState } from "react";
import { BookOpen } from "lucide-react";
import { Link } from "wouter";
import { supabase } from "@/lib/supabase";
import PlatformAdmin from "./PlatformAdmin";

export default function PlatformAdminShell() {
  const [allowed, setAllowed] = useState(false);

  useEffect(() => {
    let active = true;
    void supabase.rpc("is_platform_admin").then(({ data }) => {
      if (active) setAllowed(Boolean(data));
    });
    return () => { active = false; };
  }, []);

  return (
    <>
      <PlatformAdmin />
      {allowed && (
        <Link href="/admin/activity-content" className="fixed bottom-5 right-5 z-50 inline-flex items-center gap-2 rounded-full border border-[#BFC8C1] bg-[#FFFDF8] px-4 py-3 text-sm font-semibold text-[#355447] shadow-lg transition hover:bg-[#EDF3EC]">
          <BookOpen size={16} />活動內容
        </Link>
      )}
    </>
  );
}
