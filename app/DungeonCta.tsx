import Link from 'next/link'
import { JetBrains_Mono } from 'next/font/google'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default function DungeonCta() {
  return (
    <Link
      href="/dungeon"
      className="flex items-center gap-3 rounded-[18px] border border-[#e09595]/30
        bg-gradient-to-r from-[#8c3f3f]/35 to-[#8c3f3f]/[0.08] px-4 py-3.5 mb-4"
    >
      <div className="w-10 h-10 rounded-xl bg-[#8c3f3f]/30 flex items-center justify-center shrink-0">
        <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#f0a8a8" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="8" cy="15" r="4" />
          <path d="M11 12 20 3M17 6l2.5 2.5M14 9l2 2" />
        </svg>
      </div>
      <div className="flex-grow">
        <div className="text-[14px] font-bold text-white">Vào Dungeon</div>
        <div className={`${mono.className} text-[10px] text-[#d3a3a3] mt-0.5`}>Tiếp tục hành trình</div>
      </div>
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#f0c0c0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M9 6l6 6-6 6" />
      </svg>
    </Link>
  )
}
