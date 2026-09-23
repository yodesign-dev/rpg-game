import { SupabaseClient } from '@supabase/supabase-js'

type CharacterApFields = {
  id: string
  current_ap: number
}

// Hồi AP kiểu lazy qua RPC apply_ap_regen: DB tự tính số tick đã trôi qua từ
// lần cập nhật gần nhất theo now() của server và ghi lại nếu có tick mới
// (client không còn được update current_ap trực tiếp). Dùng chung cho mọi
// trang đọc AP của nhân vật, để AP không bị "đứng hình" khi người chơi vào
// thẳng một trang không phải trang chủ.
export async function applyApRegen(
  supabase: SupabaseClient,
  character: CharacterApFields
): Promise<{ currentAp: number; nextApMinutes: number | null }> {
  const { data, error } = await supabase
    .rpc('apply_ap_regen', { p_character_id: character.id })
    .single<{ out_current_ap: number; out_next_ap_minutes: number | null }>()

  if (error || !data) {
    console.error('apply_ap_regen failed', error)
    return { currentAp: character.current_ap, nextApMinutes: null }
  }

  return { currentAp: data.out_current_ap, nextApMinutes: data.out_next_ap_minutes }
}
