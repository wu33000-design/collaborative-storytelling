import { useEffect, useState } from "react";
import { Trash2 } from "lucide-react";
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
        <Link href="/admin/activity-delete" className="fixed bottom-5 right-5 z-50 inline-flex items-center gap-2 rounded-full border border-[#D8AAA0] bg-[#FFFDF8] px-4 py-3 text-sm font-semibold text-[#9B4637] shadow-lg transition hover:bg-[#F7E5DF]">
          <Trash2 size={16} />刪除活動
        </Link>
      )}
    </>
  );
}
