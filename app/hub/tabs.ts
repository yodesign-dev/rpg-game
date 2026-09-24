// Dùng được cả ở server lẫn client (không đặt trong file 'use client')
export type HubTab = 'overview' | 'stats' | 'talents' | 'quests'

export const HUB_TABS: { key: HubTab; label: string }[] = [
  { key: 'overview', label: 'Tổng quan' },
  { key: 'stats', label: 'Chỉ số' },
  { key: 'talents', label: 'Thiên phú' },
  { key: 'quests', label: 'Nhiệm vụ' },
]

export function parseHubTab(value: string | null | undefined): HubTab {
  return HUB_TABS.some((t) => t.key === value) ? (value as HubTab) : 'overview'
}

export function hubHref(tab: HubTab) {
  return tab === 'overview' ? '/' : `/?tab=${tab}`
}
