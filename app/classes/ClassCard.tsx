import ClassArt from '../ClassArt'
import SkillIcon from '../components/SkillIcon'

export type ClassInfo = {
  key: string
  name: string
  description: string
  main_stat: string
  auto_preset: Record<string, number>
  base_hp: number
  base_atk: number
  base_def: number
  base_spd: number
  hp_per_level: number
  atk_per_level: number
  def_per_level: number
  skills: {
    key: string
    name: string
    description: string
    skill_type: 'active' | 'passive'
    cooldown?: number
    icon?: string | null
    power_multiplier: number | null
    unlock_level: number
  }[]
}

const STAT_NAME: Record<string, string> = { str: 'STR', int: 'INT', agi: 'AGI', dex: 'DEX', vit: 'VIT' }

// Thẻ thông tin 1 lớp nhân vật: art, main stat, mô tả, chỉ số gốc, skill
export default function ClassCard({ c, highlight = false }: { c: ClassInfo; highlight?: boolean }) {
  const actives = c.skills.filter((s) => s.skill_type === 'active').sort((a, b) => a.unlock_level - b.unlock_level)
  const passives = c.skills.filter((s) => s.skill_type === 'passive')
  const preset = Object.entries(c.auto_preset ?? {})
    .map(([k, v]) => `${v} ${STAT_NAME[k] ?? k}`)
    .join(' + ')

  return (
    <div
      className={`rounded-2xl border p-4 bg-[#141a26] ${highlight ? 'border-[#f0c060]/60' : 'border-white/[0.08]'}`}
    >
      <div className="flex items-center gap-3">
        <ClassArt classKey={c.key} seed={c.key} size={48} />
        <h3 className="text-lg font-bold text-white">
          {c.name}
          {highlight && <span className="ml-2 text-xs font-normal text-[#f0c060]">(bạn)</span>}
        </h3>
      </div>

      <p className="mt-3 rounded-md bg-[#2a3350] px-2.5 py-1 text-xs font-semibold text-[#f0d060]">
        Main stat: {STAT_NAME[c.main_stat] ?? c.main_stat}
        <span className="font-normal text-[#a8b0d0]"> · Tự cộng: {preset}</span>
      </p>

      <p className="mt-3 text-sm text-[#e5e1ed] leading-relaxed">{c.description}</p>

      <p className="mt-2 text-xs text-[#8a93b0]">
        HP {c.base_hp} (+{c.hp_per_level}/cấp) · ATK {c.base_atk} (+{c.atk_per_level}) · DEF {c.base_def} (+
        {c.def_per_level}) · SPD {c.base_spd}
      </p>

      <ul className="mt-3 space-y-1 text-xs">
        {actives.map((s) => (
          <li key={s.key} className="flex items-start gap-2 text-[#8fa4d8]">
            <SkillIcon icon={s.icon ?? null} classKey={c.key} size={24} />
            <span>
            <b className="text-[#b8c8f0]">{s.name}</b> — {s.description}
            <span className="text-[#6b7494]">
              {!!s.cooldown && ` · hồi ${s.cooldown} lượt`}
              {s.unlock_level > 1 && ` (Lv${s.unlock_level})`}
            </span>
            </span>
          </li>
        ))}
        {passives.map((s) => (
          <li key={s.key} className="flex items-start gap-2 text-[#8fa4d8]">
            <SkillIcon icon={s.icon ?? null} classKey={c.key} size={24} />
            <span>
              <b className="text-[#b8c8f0]">{s.name}</b> — {s.description}
              {s.unlock_level > 1 && <span className="text-[#6b7494]"> (Lv{s.unlock_level})</span>}
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}
