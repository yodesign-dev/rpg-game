import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import ClassCard, { type ClassInfo } from './ClassCard'

export default async function ClassesPage() {
  const { supabase, character } = await getCurrentCharacter()
  const { data } = await supabase
    .from('classes')
    .select(
      'key, name, description, main_stat, auto_preset, base_hp, base_atk, base_def, base_spd, hp_per_level, atk_per_level, def_per_level, sort_order, skills(key, name, description, skill_type, power_multiplier, unlock_level)'
    )
    .order('sort_order')
  const myClass = (character.classes as { key: string }).key

  return (
    <GlassPage title="Lớp Nhân Vật" subtitle="Chỉ số gốc, main stat và kỹ năng của từng lớp.">
      <p className="text-sm font-bold text-[#f0d060] mb-3">⚔️ Base Classes</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {((data ?? []) as ClassInfo[]).map((c) => (
          <ClassCard key={c.key} c={c} highlight={c.key === myClass} />
        ))}
      </div>
    </GlassPage>
  )
}
