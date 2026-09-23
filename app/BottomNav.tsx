'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { JetBrains_Mono } from 'next/font/google'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

const TABS = [
  {
    href: '/dungeon',
    label: 'Dungeon',
    icon: (
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="8" cy="15" r="4" />
        <path d="M11 12 20 3M17 6l2.5 2.5M14 9l2 2" />
      </svg>
    ),
  },
  {
    href: '/skills',
    label: 'Kỹ Năng',
    icon: (
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18" />
      </svg>
    ),
  },
  {
    href: '/inventory',
    label: 'Túi Đồ',
    icon: (
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M7 8V6a5 5 0 0 1 10 0v2" />
        <rect x="5" y="8" width="14" height="13" rx="2" />
        <path d="M9 12h6M9 16h6" />
      </svg>
    ),
  },
  {
    href: '/market',
    label: 'Chợ',
    icon: (
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 8h12l-1 12H7Z" />
        <path d="M9 8V6a3 3 0 0 1 6 0v2" />
      </svg>
    ),
  },
  {
    href: '/quests',
    label: 'Nhiệm Vụ',
    icon: (
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 4h9a3 3 0 0 1 3 3v11a2 2 0 0 1-2 2H8" />
        <path d="M6 4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2" />
        <path d="M9 9h6M9 13h6" />
      </svg>
    ),
  },
] as const

export default function BottomNav() {
  const pathname = usePathname()

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-30 flex items-stretch justify-around
        bg-[#0e0d12]/90 backdrop-blur-sm border-t border-white/10 pb-4 pt-2.5 px-1.5"
    >
      {TABS.map((tab) => {
        const active = pathname?.startsWith(tab.href)
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={`flex flex-col items-center gap-1 min-w-[44px] px-1 py-1 transition-colors
              ${active ? 'text-[#8fe0b0]' : 'text-[#8f96a8] hover:text-[#c7c2d3]'}`}
          >
            <span style={{ color: active ? '#8fe0b0' : 'currentColor' }}>{tab.icon}</span>
            <span className={`${mono.className} text-[9px]`}>{tab.label}</span>
          </Link>
        )
      })}
    </nav>
  )
}
