'use client'

// Thành phần hiển thị dùng chung cho Thám Hiểm và Tháp Vực Sâu

export const RARITY_TEXT: Record<string, string> = {
  common: 'text-[#c9c4d4]',
  rare: 'text-[#8fc4e0]',
  epic: 'text-[#d0a8f0]',
  legendary: 'text-[#f0c060]',
}

export type LastFight = {
  turn: number
  enemy: string
  log: {
    turn: number
    actor: 'character' | 'enemy' | 'system'
    skill?: string
    damage?: number
    crit?: boolean
    enemy_hp_left?: number
    enemy_name?: string
    character_hp_left?: number
    message?: string
    double?: boolean
    opening?: boolean
    thorns?: number
    echo?: boolean
    parry?: number
    revive?: boolean
    stun?: boolean
    stunned?: boolean
    dot?: boolean
  }[]
}

export function Meter({ label, value, max, color, note }: { label: string; value: number; max: number; color: string; note: string }) {
  const pct = Math.min(100, Math.round((value / Math.max(1, max)) * 100))
  return (
    <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-3">
      <div className="flex justify-between text-xs text-[#a29fb3] mb-2">
        <span>{label}</span>
        <span className="text-sm text-white">
          {value} / {max}
        </span>
      </div>
      <div className="h-2 rounded-full bg-white/[0.07] overflow-hidden">
        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
      {value < max && <p className="text-xs text-[#7d7a8c] text-right mt-1.5">{note}</p>}
    </div>
  )
}

export function LastFightLog({ fight }: { fight: LastFight }) {
  return (
    <div className="mt-2 max-h-64 overflow-y-auto space-y-1 border-l border-white/[0.1] pl-3">
      {fight.log.map((e, i) => (
        <p key={i} className="text-xs leading-relaxed">
          {e.actor === 'character' ? (
            <span className="text-[#c9c4d4]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> {e.double ? '⚡ Đòn Kép!' : e.echo ? '✨' : e.dot ? '☠️' : '⚔️'}{' '}
              {e.opening && <span className="text-[#f0c060]">Khai Cuộc! </span>}
              {e.skill} gây{' '}
              <b className={e.crit ? 'text-[#f0c060]' : 'text-white'}>{e.damage}</b>
              {e.crit && ' (chí mạng!)'}
              {e.stun && <span className="text-[#8fc4e0]"> ❄️ đóng băng!</span>} · {fight.enemy} còn {e.enemy_hp_left} HP
            </span>
          ) : e.actor === 'enemy' && e.stunned ? (
            <span className="text-[#8fc4e0]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> ❄️ {e.enemy_name} bị đóng băng, mất lượt
            </span>
          ) : e.actor === 'enemy' && e.parry ? (
            <span className="text-[#8fe0b0]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> 🛡️ Phản Kích! Đỡ đòn {e.enemy_name}, phản {e.parry} ·{' '}
              {fight.enemy} còn {e.enemy_hp_left} HP
            </span>
          ) : e.actor === 'enemy' ? (
            <span className="text-[#e09595]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> 🩸 {e.enemy_name} đánh {e.damage} · bạn còn{' '}
              {e.character_hp_left} HP
              {!!e.thorns && <span className="text-[#f0c060]"> · 🌵 Phản Đòn {e.thorns}</span>}
            </span>
          ) : (
            <span className="text-[#f0c060]">⏱️ {e.message}</span>
          )}
        </p>
      ))}
    </div>
  )
}

export function ItemIcon({ icon, size }: { icon: string | null; size: number }) {
  if (!icon) return null
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={`/items/${icon}`} alt="" width={size} height={size} className="[image-rendering:pixelated]" />
}
