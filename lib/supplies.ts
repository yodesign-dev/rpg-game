import type { SupabaseClient } from '@supabase/supabase-js'

// Số bình máu (hồi theo %) trong túi + cuộn/bùa đang chờ — cho thanh Tiếp tế
export async function getSupplies(supabase: SupabaseClient, characterId: string) {
  const [{ data: inv }, { data: buffs }] = await Promise.all([
    supabase.from('inventory').select('quantity, items!inner(heal_pct)').eq('character_id', characterId).gt('items.heal_pct', 0),
    supabase.from('character_buffs').select('buff_key').eq('character_id', characterId),
  ])
  return {
    potionCount: (inv ?? []).reduce((sum, r) => sum + (r.quantity ?? 0), 0),
    buffs: (buffs ?? []).map((b) => b.buff_key as string),
  }
}
