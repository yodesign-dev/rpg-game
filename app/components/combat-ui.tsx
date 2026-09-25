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
    actor: 'character' | 'enemy' | 'pet' | 'system'
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
    // Đặc tính quái
    miss?: boolean
    reflect?: number
    enemy_crit?: boolean
    enraged?: boolean
    poison?: number
    regen?: number
    // Skill hỗ trợ / lá chắn / pet
    buff?: boolean
    blocked?: boolean
    shield?: number
    pet_name?: string
    pet_skill?: string | null
    heal?: number
  }[]
}

export function Meter({
  label,
  value,
  max,
  color,
  note,
  action,
}: {
  label: string
  value: number
  max: number
  color: string
  note: string
  action?: React.ReactNode // vd. nút Hồi đầy, hiện khi chưa đầy
}) {
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
      {value < max && action}
    </div>
  )
}

// Skill pet trong nhật ký trận (khớp simulate_fight: v_pet_skill)
const PET_SKILL_LOG: Record<string, string> = {
  heal: '💚 Chữa Lành',
  guard: '🛡️ Hộ Thân',
  freeze: '❄️ Hơi Băng',
  bleed: '🩸 Cắn Xé',
  poison: '🐍 Phun Độc',
  burn: '🔥 Phun Lửa',
}

export function LastFightLog({ fight }: { fight: LastFight }) {
  return (
    <div className="mt-2 max-h-64 overflow-y-auto space-y-1 border-l border-white/[0.1] pl-3">
      {fight.log.map((e, i) => (
        <p key={i} className="text-xs leading-relaxed">
          {e.actor === 'character' && e.buff ? (
            <span className="text-[#8fc4e0]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> ✨ {e.skill}: {e.message}
            </span>
          ) : e.actor === 'pet' ? (
            <span className="text-[#c8f5dc]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> 🐾 {e.pet_name}
              {e.pet_skill && <b> {PET_SKILL_LOG[e.pet_skill] ?? e.pet_skill}</b>}
              {!!e.heal && <span> · hồi {e.heal} HP</span>}
              {e.stun && <span className="text-[#8fc4e0]"> · ❄️ đóng băng!</span>} · cắn <b className="text-white">{e.damage}</b> ·{' '}
              {fight.enemy} còn {e.enemy_hp_left} HP
            </span>
          ) : e.actor === 'enemy' && e.blocked ? (
            <span className="text-[#8fc4e0]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> 🛡️ Đòn của {e.enemy_name} bị chặn / né
            </span>
          ) : e.actor === 'character' && e.miss ? (
            <span className="text-[#7d7a8c]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> 💨 {e.skill} trượt — {fight.enemy} né được
            </span>
          ) : e.actor === 'character' ? (
            <span className="text-[#c9c4d4]">
              <span className="text-[#7d7a8c]">#{e.turn}</span> {e.double ? '⚡ Đòn Kép!' : e.echo ? '✨' : e.dot ? '☠️' : '⚔️'}{' '}
              {e.opening && <span className="text-[#f0c060]">Khai Cuộc! </span>}
              {e.skill} gây{' '}
              <b className={e.crit ? 'text-[#f0c060]' : 'text-white'}>{e.damage}</b>
              {e.crit && ' (chí mạng!)'}
              {e.stun && <span className="text-[#8fc4e0]"> ❄️ đóng băng!</span>} · {fight.enemy} còn {e.enemy_hp_left} HP
              {!!e.reflect && <span className="text-[#e09595]"> · 🦔 gai phản {e.reflect}</span>}
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
              <span className="text-[#7d7a8c]">#{e.turn}</span> {e.enraged && <b>😡 Cuồng Nộ! </b>}🩸 {e.enemy_name} đánh{' '}
              <b className={e.enemy_crit ? 'text-[#ff8080]' : undefined}>{e.damage}</b>
              {e.enemy_crit && ' (chí mạng!)'}
              {!!e.shield && <span className="text-[#8fc4e0]"> · 🔮 lá chắn đỡ {e.shield}</span>}
              {!!e.poison && <span> · 🐍 độc −{e.poison}</span>} · bạn còn {e.character_hp_left} HP
              {!!e.thorns && <span className="text-[#f0c060]"> · 🌵 Phản Đòn {e.thorns}</span>}
              {!!e.regen && <span className="text-[#8fe0b0]"> · 💚 quái hồi {e.regen}</span>}
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
