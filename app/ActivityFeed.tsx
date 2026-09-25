'use client'

import { useState } from 'react'
import { ui } from '@/app/fonts'
import { LEGENDARY_EFFECTS } from '@/lib/legendary-effects'

const COLLAPSED = 3

export type FeedEntry = {
  id: string
  character_id: string | null
  character_name: string
  character_title: string | null
  kind: 'boss_kill' | 'legendary_item' | 'title' | 'tower' | 'gacha_jackpot' | 'pet_catch'
  payload: {
    boss?: string
    where?: string
    item?: string
    icon?: string | null
    effect?: string | null
    title?: string
    emoji?: string
    floor?: number
    pet?: string
  }
  created_at: string
}

function timeAgo(iso: string, now: number) {
  const mins = Math.max(0, Math.floor((now - new Date(iso).getTime()) / 60000))
  if (mins < 1) return 'vừa xong'
  if (mins < 60) return `${mins} phút trước`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours} giờ trước`
  return `${Math.floor(hours / 24)} ngày trước`
}

// Bảng tin chung của mọi người chơi: hạ boss + nhận đồ Huyền Thoại
export default function ActivityFeed({
  entries,
  myCharacterId,
  now,
}: {
  entries: FeedEntry[]
  myCharacterId: string
  now: number
}) {
  const [expanded, setExpanded] = useState(false)
  const shown = expanded ? entries : entries.slice(0, COLLAPSED)

  return (
    <div className={`${ui.className} rounded-[18px] bg-white/[0.045] border border-white/[0.09] p-4`}>
      <div className="text-xs font-semibold tracking-[2px] text-[#a29fb3] mb-3">BẢNG TIN</div>

      {entries.length === 0 ? (
        <p className="text-xs text-[#7d7a8c]">Chưa có ai hạ boss hay nhặt đồ Huyền Thoại. Người đầu tiên sẽ là bạn?</p>
      ) : (
        <ul className="space-y-2.5">
          {shown.map((e) => {
            const mine = e.character_id === myCharacterId
            const name = (
              <>
                {e.character_title && <span className="text-[#f0c060]/80">[{e.character_title}] </span>}
                <b className={mine ? 'text-[#e3caf5]' : 'text-white'}>
                  {e.character_name}
                  {mine && ' (bạn)'}
                </b>
              </>
            )
            const effect = e.payload.effect ? LEGENDARY_EFFECTS[e.payload.effect] : null
            return (
              <li key={e.id} className="flex gap-2.5 text-xs leading-relaxed">
                <span className="shrink-0 text-base leading-5">
                  {e.kind === 'boss_kill' ? '👑' : e.kind === 'pet_catch' ? '🐾' : e.kind === 'title' ? '🎖️' : e.kind === 'tower' ? '🗼' : e.kind === 'gacha_jackpot' ? '💎' : '✨'}
                </span>
                <div className="min-w-0">
                  {e.kind === 'pet_catch' ? (
                    <p className="text-[#c9c4d4]">
                      {name} đã bắt được pet <b className="text-[#f0c060]">{e.payload.pet}</b> Huyền Thoại!
                    </p>
                  ) : e.kind === 'gacha_jackpot' ? (
                    <p className="text-[#c9c4d4]">
                      {name} trúng <b className="text-[#f7c8f7]">JACKPOT</b> ở Thương Nhân Bí Ẩn:{' '}
                      <b className="text-[#f0c060]">{e.payload.item}</b>!
                    </p>
                  ) : e.kind === 'tower' ? (
                    <p className="text-[#c9c4d4]">
                      {name} đã chinh phục <b className="text-[#c8a8f0]">tầng {e.payload.floor}</b> Tháp Vực Sâu!
                    </p>
                  ) : e.kind === 'title' ? (
                    <p className="text-[#c9c4d4]">
                      {name} đạt danh hiệu{' '}
                      <b className="text-[#f0c060]">
                        {e.payload.emoji} {e.payload.title}
                      </b>
                    </p>
                  ) : e.kind === 'boss_kill' ? (
                    <p className="text-[#c9c4d4]">
                      {name} đã hạ Boss <b className="text-[#f0a8a8]">{e.payload.boss}</b>
                      {e.payload.where && <> tại {e.payload.where}</>}!
                    </p>
                  ) : (
                    <p className="text-[#c9c4d4]">
                      {name} nhận được <b className="text-[#f0c060]">{e.payload.item}</b> Huyền Thoại
                      {effect && <span className="text-[#f0c060]/80"> · {effect.name}</span>}
                    </p>
                  )}
                  <p className="text-xs text-[#7d7a8c]">{timeAgo(e.created_at, now)}</p>
                </div>
              </li>
            )
          })}
        </ul>
      )}
      {entries.length > COLLAPSED && (
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="mt-3 text-xs text-[#a29fb3] hover:text-white"
        >
          {expanded ? 'Thu gọn' : `Xem thêm ${entries.length - COLLAPSED} tin`}
        </button>
      )}
    </div>
  )
}
