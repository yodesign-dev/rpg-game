import { SupabaseClient } from '@supabase/supabase-js'

type CharacterRegenFields = {
  id: string
  current_ap: number
  current_hp: number | null
}

// Hồi AP + HP kiểu lazy qua RPC apply_regen: DB tự tính số tick đã trôi qua
// từ lần cập nhật gần nhất theo now() của server (+1 AP mỗi ap_regen_minutes
// phút, +2% HP tối đa mỗi phút) và ghi lại nếu có tick mới — client không
// được update current_ap/current_hp trực tiếp. Dùng chung cho mọi trang đọc
// AP/HP, để số không bị "đứng hình" khi người chơi vào thẳng trang nào đó.
// currentHp null = không đọc được (trang tự lấy max HP làm mặc định).
export async function applyRegen(
  supabase: SupabaseClient,
  character: CharacterRegenFields
): Promise<{ currentAp: number; nextApMinutes: number | null; currentHp: number | null }> {
  const { data, error } = await supabase
    .rpc('apply_regen', { p_character_id: character.id })
    .single<{ out_current_ap: number; out_next_ap_minutes: number | null; out_current_hp: number }>()

  if (error || !data) {
    console.error('apply_regen failed', error)
    return { currentAp: character.current_ap, nextApMinutes: null, currentHp: character.current_hp }
  }

  return {
    currentAp: data.out_current_ap,
    nextApMinutes: data.out_next_ap_minutes,
    currentHp: data.out_current_hp,
  }
}
