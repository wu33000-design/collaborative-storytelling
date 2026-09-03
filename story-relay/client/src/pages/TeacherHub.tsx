import { Monitor } from "lucide-react";
import { Link } from "wouter";
import CreateActivity from "./CreateActivity";

export default function TeacherHub() {
  return (
    <>
      <CreateActivity />
      <Link
        href="/teacher"
        className="fixed bottom-5 left-5 z-40 inline-flex items-center gap-2 rounded-full border border-[#BFC8C1] bg-[#FFFDF8] px-4 py-2.5 text-sm font-semibold text-[#355447] shadow-md transition hover:bg-[#EDF3EC]"
      >
        <Monitor size={16} />
        活動監控
      </Link>
    </>
  );
}
