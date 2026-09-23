import { SupabaseClient } from '@supabase/supabase-js'

type CharacterApFields = {
  id: string
  current_ap: number
  max_ap: number
  last_ap_update: string
  ap_regen_minutes: number
}

// Hồi AP kiểu lazy: tính số tick đã trôi qua từ lần cập nhật gần nhất và
// ghi lại vào DB nếu có tick mới. Dùng chung cho mọi trang đọc AP của nhân
// vật, để AP không bị "đứng hình" khi người chơi vào thẳng một trang không
// phải trang chủ.
export async function applyApRegen(
  supabase: SupabaseClient,
  character: CharacterApFields
): Promise<{ currentAp: number; nextApMinutes: number | null }> {
  const lastUpdate = new Date(character.last_ap_update)
  const elapsedMs = Date.now() - lastUpdate.getTime()
  const elapsedMinutes = Math.floor(elapsedMs / 60000)
  const regenTicks = Math.floor(elapsedMinutes / character.ap_regen_minutes)

  let currentAp = character.current_ap
  let nextApMinutes: number | null = null

  if (regenTicks > 0 && character.current_ap < character.max_ap) {
    const newAp = Math.min(character.max_ap, character.current_ap + regenTicks)
    const newLastUpdate = new Date(
      lastUpdate.getTime() + regenTicks * character.ap_regen_minutes * 60000
    )
    await supabase
      .from('characters')
      .update({ current_ap: newAp, last_ap_update: newLastUpdate.toISOString() })
      .eq('id', character.id)
    currentAp = newAp
  }

  if (currentAp < character.max_ap) {
    nextApMinutes = character.ap_regen_minutes - (elapsedMinutes % character.ap_regen_minutes)
  }

  return { currentAp, nextApMinutes }
}
