import Link from 'next/link'

export type HubTab = 'overview' | 'stats' | 'talents' | 'quests'

export const HUB_TABS: { key: HubTab; label: string }[] = [
  { key: 'overview', label: 'Tổng quan' },
  { key: 'stats', label: 'Chỉ số' },
  { key: 'talents', label: 'Thiên phú' },
  { key: 'quests', label: 'Nhiệm vụ' },
]

export function parseHubTab(value: string | undefined): HubTab {
  return HUB_TABS.some((t) => t.key === value) ? (value as HubTab) : 'overview'
}

export function hubHref(tab: HubTab) {
  return tab === 'overview' ? '/' : `/?tab=${tab}`
}

// Tab con của màn Nhân Vật — số đỏ = việc đang chờ (điểm chưa cộng, quà chưa nhận)
export default function HubTabs({ active, badges }: { active: HubTab; badges: Partial<Record<HubTab, number>> }) {
  return (
    <nav className="flex border-b border-white/10 mb-4" aria-label="Mục nhân vật">
      {HUB_TABS.map((t) => {
        const on = t.key === active
        const badge = badges[t.key] ?? 0
        return (
          <Link
            key={t.key}
            href={hubHref(t.key)}
            scroll={false}
            aria-current={on ? 'page' : undefined}
            className={`relative flex-1 flex items-center justify-center gap-1 whitespace-nowrap px-1 py-3 text-sm font-medium transition-colors
              ${on ? 'text-[#8fe0b0]' : 'text-[#a29fb3] hover:text-white'}`}
          >
            {t.label}
            {badge > 0 && (
              <span className="min-w-[18px] h-[18px] px-1 rounded-full bg-[#e0566b] text-white text-[11px] font-semibold leading-[18px] text-center">
                {badge}
              </span>
            )}
            {on && <span className="absolute left-2 right-2 -bottom-px h-0.5 rounded-full bg-[#8fe0b0]" />}
          </Link>
        )
      })}
    </nav>
  )
}
