'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ui } from '@/app/fonts'

// center: nút giữa nổi lên — hoạt động chính của game
type Tab = { href: string; label: string; match?: string[]; center?: boolean; icon: React.ReactNode }

const TABS: Tab[] = [
  {
    href: '/',
    label: 'Nhân Vật',
    // các trang con mở từ màn nhân vật vẫn tính là tab này
    match: ['/talents', '/classes', '/titles', '/ranking', '/training', '/quests', '/explore'],
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="8" r="4" />
        <path d="M4 21a8 8 0 0 1 16 0" />
      </svg>
    ),
  },
  {
    href: '/skills',
    label: 'Kỹ Năng',
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18" />
      </svg>
    ),
  },
  {
    href: '/dungeon',
    label: 'Tháp',
    center: true,
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="8" cy="15" r="4" />
        <path d="M11 12 20 3M17 6l2.5 2.5M14 9l2 2" />
      </svg>
    ),
  },
  {
    href: '/inventory',
    label: 'Túi Đồ',
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
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
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 8h12l-1 12H7Z" />
        <path d="M9 8V6a3 3 0 0 1 6 0v2" />
      </svg>
    ),
  },
]

export default function BottomNav() {
  const pathname = usePathname()

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-30 bg-[#0e0d12]/90 backdrop-blur-sm border-t border-white/10">
      <div className="mx-auto max-w-2xl flex items-end justify-around pb-4 pt-2.5 px-3">
        {TABS.map((tab) => {
          const active =
            tab.href === '/'
              ? pathname === '/' || !!tab.match?.some((m) => pathname?.startsWith(m))
              : pathname?.startsWith(tab.href)
          if (tab.center) {
            return (
              <Link
                key={tab.href}
                href={tab.href}
                aria-current={active ? 'page' : undefined}
                className="flex flex-col items-center gap-1 min-w-[64px] -mt-6"
              >
                <span
                  className={`w-14 h-14 rounded-full flex items-center justify-center border-2 shadow-lg shadow-black/50 transition-colors
                    ${active ? 'bg-[#8c3f3f] border-[#f0a8a8] text-white' : 'bg-[#3a1f24] border-[#e09595]/60 text-[#f0c0c0] hover:bg-[#5a2a30]'}`}
                >
                  {tab.icon}
                </span>
                <span className={`${ui.className} text-xs font-semibold ${active ? 'text-[#f0c0c0]' : 'text-[#c7c2d3]'}`}>
                  {tab.label}
                </span>
              </Link>
            )
          }
          return (
            <Link
              key={tab.href}
              href={tab.href}
              aria-current={active ? 'page' : undefined}
              className={`flex flex-col items-center gap-1.5 min-w-[56px] px-1.5 py-1.5 rounded-xl transition-colors
                ${active ? 'text-[#8fe0b0] bg-[#8fe0b0]/10' : 'text-[#8f96a8] hover:text-[#c7c2d3]'}`}
            >
              <span style={{ color: active ? '#8fe0b0' : 'currentColor' }}>{tab.icon}</span>
              <span className={`${ui.className} text-xs font-medium`}>{tab.label}</span>
            </Link>
          )
        })}
      </div>
    </nav>
  )
}
