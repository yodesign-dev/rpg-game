'use client'

import { useSearchParams } from 'next/navigation'
import { HUB_TABS, hubHref, parseHubTab, type HubTab } from './tabs'

// Tab con của màn Nhân Vật đổi hoàn toàn phía client: server đã render sẵn cả 4 panel,
// ở đây chỉ ẩn/hiện + ghi ?tab= vào URL bằng history.pushState (Next đồng bộ với
// useSearchParams, nút Back vẫn chạy) — không gọi lại server nên đổi tab là tức thì.
function useActiveTab() {
  return parseHubTab(useSearchParams().get('tab'))
}

function go(e: React.MouseEvent<HTMLAnchorElement>, tab: HubTab) {
  // Ctrl/Cmd/giữa chuột: để trình duyệt mở tab mới như link thường
  if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return
  e.preventDefault()
  window.history.pushState(null, '', hubHref(tab))
}

// Link sang một tab con từ bất kỳ đâu trong màn Nhân Vật (thẻ tóm tắt, ô chỉ số…)
export function HubLink({ tab, className, children }: { tab: HubTab; className?: string; children: React.ReactNode }) {
  return (
    <a href={hubHref(tab)} onClick={(e) => go(e, tab)} className={className}>
      {children}
    </a>
  )
}

// Giữ panel đã mount (chỉ ẩn) để state bên trong — cây thiên phú, form cộng điểm — không mất khi đổi qua lại
export function HubPanel({ tab, children }: { tab: HubTab; children: React.ReactNode }) {
  return <div hidden={useActiveTab() !== tab}>{children}</div>
}

// số đỏ = việc đang chờ (điểm chưa cộng, quà chưa nhận)
export default function HubTabs({ badges }: { badges: Partial<Record<HubTab, number>> }) {
  const active = useActiveTab()
  return (
    <nav className="flex border-b border-white/10 mb-4" aria-label="Mục nhân vật">
      {HUB_TABS.map((t) => {
        const on = t.key === active
        const badge = badges[t.key] ?? 0
        return (
          <a
            key={t.key}
            href={hubHref(t.key)}
            onClick={(e) => go(e, t.key)}
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
          </a>
        )
      })}
    </nav>
  )
}
