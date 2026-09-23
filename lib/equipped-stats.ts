import { SupabaseClient } from '@supabase/supabase-js'

export type EquippedStats = {
  bonusAtk: number
  bonusDef: number
  bonusHp: number
  critBonus: number
  lifestealBonus: number
}

const EMPTY: EquippedStats = { bonusAtk: 0, bonusDef: 0, bonusHp: 0, critBonus: 0, lifestealBonus: 0 }

// Tổng chỉ số từ trang bị đang mặc — bao gồm cả affix roll ngẫu nhiên
// (rolled_atk/def/hp/crit/lifesteal trên từng dòng inventory), không chỉ
// stat gốc của item. Dùng để tính max_hp hiển thị khớp với công thức thật
// trong resolve_dungeon_floor (schema.sql), vì bonus_hp/rolled_hp giờ ảnh
// hưởng thật đến HP tối đa trong combat, không còn chỉ là text trang trí.
export async function getEquippedStats(
  supabase: SupabaseClient,
  characterId: string
): Promise<EquippedStats> {
  const { data } = await supabase
    .from('inventory')
    .select('rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal, items(bonus_atk, bonus_def, bonus_hp)')
    .eq('character_id', characterId)
    .eq('equipped', true)

  const rows = (data as any[]) ?? []

  return rows.reduce((acc, r) => {
    const item = r.items ?? {}
    return {
      bonusAtk: acc.bonusAtk + (item.bonus_atk ?? 0) + r.rolled_atk,
      bonusDef: acc.bonusDef + (item.bonus_def ?? 0) + r.rolled_def,
      bonusHp: acc.bonusHp + (item.bonus_hp ?? 0) + r.rolled_hp,
      critBonus: acc.critBonus + Number(r.rolled_crit ?? 0),
      lifestealBonus: acc.lifestealBonus + Number(r.rolled_lifesteal ?? 0),
    }
  }, EMPTY)
}
