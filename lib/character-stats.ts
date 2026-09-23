import { SupabaseClient } from '@supabase/supabase-js'

export type CharacterStats = {
  // Class + cấp + điểm chỉ số, chưa cộng trang bị
  baseMaxHp: number
  baseAtk: number
  baseDef: number
  baseSpd: number
  attrCrit: number
  // Đã cộng trang bị (kể cả affix roll) — đúng số dùng trong combat
  maxHp: number
  atk: number
  def: number
  critBonus: number
  lifestealBonus: number
}

// Đọc từ RPC get_character_stats (schema.sql) — nguồn công thức duy nhất cho
// HP/ATK/DEF, dùng chung với resolve_dungeon_floor và use_item để số trên UI
// không bao giờ lệch với số trong trận.
export async function getCharacterStats(
  supabase: SupabaseClient,
  characterId: string
): Promise<CharacterStats> {
  const { data, error } = await supabase.rpc('get_character_stats', { p_character_id: characterId })
  const r = (Array.isArray(data) ? data[0] : data) as Record<string, number | string> | undefined

  if (error || !r) throw new Error(`Không tải được chỉ số nhân vật: ${error?.message ?? 'không có dữ liệu'}`)

  return {
    baseMaxHp: Number(r.base_max_hp),
    baseAtk: Number(r.base_atk),
    baseDef: Number(r.base_def),
    baseSpd: Number(r.base_spd),
    attrCrit: Number(r.attr_crit),
    maxHp: Number(r.max_hp),
    atk: Number(r.atk),
    def: Number(r.def),
    critBonus: Number(r.crit_bonus),
    lifestealBonus: Number(r.lifesteal_bonus),
  }
}

export type AttributeKey = 'str' | 'int' | 'agi' | 'dex' | 'vit'
export type Attributes = Record<AttributeKey, number>

export const ATTRIBUTE_KEYS: AttributeKey[] = ['str', 'int', 'agi', 'dex', 'vit']

// Mỗi cấp được bao nhiêu điểm — khớp với add_experience
export const STAT_POINTS_PER_LEVEL = 3

// Bản sao phía client của attribute_bonuses (schema.sql), CHỈ dùng để xem
// trước "ATK 42 → 45" trước khi bấm xác nhận. Số thật luôn lấy từ server.
export function attributeBonuses(mainStat: string, a: Attributes) {
  return {
    atk: mainStat in a ? a[mainStat as AttributeKey] : 0,
    def: Math.floor(a.vit / 2),
    hp: a.vit * 5,
    crit: a.agi * 0.005 + a.dex * 0.003,
  }
}

export const ATTRIBUTE_INFO: Record<AttributeKey, { label: string; name: string; effect: (isMain: boolean) => string }> = {
  str: { label: 'STR', name: 'Sức Mạnh', effect: (m) => (m ? '+1 ATK' : 'Không tăng ATK') },
  int: { label: 'INT', name: 'Trí Tuệ', effect: (m) => (m ? '+1 ATK phép' : 'Không tăng ATK') },
  agi: { label: 'AGI', name: 'Nhanh Nhẹn', effect: (m) => (m ? '+1 ATK · +0.5% crit' : '+0.5% crit') },
  dex: { label: 'DEX', name: 'Khéo Léo', effect: (m) => (m ? '+1 ATK · +0.3% crit' : '+0.3% crit') },
  vit: { label: 'VIT', name: 'Thể Lực', effect: () => '+5 HP · +1 DEF / 2 điểm' },
}
