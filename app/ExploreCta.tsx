import Link from 'next/link'
import { JetBrains_Mono } from 'next/font/google'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default function ExploreCta() {
  return (
    <Link
      href="/explore"
      className="flex items-center gap-4 rounded-[18px] border border-[#8fe0b0]/30
        bg-gradient-to-r from-[#3d6b52]/40 to-[#3d6b52]/[0.08] px-5 py-4 mb-4
        hover:border-[#8fe0b0]/50 transition-colors"
    >
      <div className="w-12 h-12 rounded-xl bg-[#3d6b52]/35 flex items-center justify-center shrink-0">
        <svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="#a8f0c8" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="9" />
          <path d="m15.5 8.5-2 5-5 2 2-5Z" />
        </svg>
      </div>
      <div className="flex-grow">
        <div className="text-lg font-bold text-white">Thám Hiểm</div>
        <div className={`${mono.className} text-xs text-[#b8e0c8] mt-0.5`}>Cày quái theo vùng, tối đa 100 lượt</div>
      </div>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#c0f0d0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M9 6l6 6-6 6" />
      </svg>
    </Link>
  )
}
