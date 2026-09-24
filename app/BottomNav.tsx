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
        {/* Chân dung nhân vật */}
        <circle cx="12" cy="12" r="9.5" />
        <circle cx="12" cy="10" r="3.2" />
        <path d="M6.3 18.7a6.5 6.5 0 0 1 11.4 0" />
      </svg>
    ),
  },
  {
    href: '/skills',
    label: 'Kỹ Năng',
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        {/* Tia sét — kỹ năng */}
        <path d="M13 2 4 14h7l-1 8 9-12h-7Z" />
      </svg>
    ),
  },
  {
    href: '/dungeon',
    label: 'Tháp',
    center: true,
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        {/* Tháp có lỗ châu mai */}
        <path d="M6 21V9H5V3h3v2h2.5V3h3v2H16V3h3v6h-1v12Z" />
        <path d="M10 21v-4a2 2 0 0 1 4 0v4M12 11v2" />
      </svg>
    ),
  },
  {
    href: '/inventory',
    label: 'Túi Đồ',
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        {/* Túi vải buộc dây */}
        <path d="M9 3h6l-1.5 3.5h-3Z" />
        <path d="M10.5 6.5C6.5 8.5 4 12.5 4 16a4 4 0 0 0 4 4h8a4 4 0 0 0 4-4c0-3.5-2.5-7.5-6.5-9.5" />
        <path d="M9.5 9.5h5" />
      </svg>
    ),
  },
  {
    href: '/market',
    label: 'Chợ',
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        {/* Sạp chợ có mái che */}
        <path d="M3 9 5 4h14l2 5" />
        <path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0" />
        <path d="M5 11.5V21h14v-9.5M9.5 21v-5h5v5" />
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
