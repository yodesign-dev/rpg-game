import Link from 'next/link'
import { ui } from '@/app/fonts'


export default function DungeonCta() {
  return (
    <Link
      href="/dungeon"
      className="flex items-center gap-4 rounded-[18px] border border-[#e09595]/30
        bg-gradient-to-r from-[#8c3f3f]/35 to-[#8c3f3f]/[0.08] px-5 py-4 mb-4
        hover:border-[#e09595]/50 transition-colors"
    >
      <div className="w-12 h-12 rounded-xl bg-[#8c3f3f]/30 flex items-center justify-center shrink-0">
        <svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="#f0a8a8" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="8" cy="15" r="4" />
          <path d="M11 12 20 3M17 6l2.5 2.5M14 9l2 2" />
        </svg>
      </div>
      <div className="flex-grow">
        <div className="text-lg font-bold text-white">Tháp Vực Sâu</div>
        <div className={`${ui.className} text-xs text-[#e0b8b8] mt-0.5`}>100 tầng · càng cao càng khó, thưởng càng lớn</div>
      </div>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#f0c0c0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M9 6l6 6-6 6" />
      </svg>
    </Link>
  )
}
