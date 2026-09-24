// Cột inventory mà Túi Đồ cần — dùng chung cho lần tải đầu (server) và các lần
// tải lại sau khi chế tạo/cường hóa/rã ghép (client) để hai bên không lệch nhau.
export const INVENTORY_SELECT =
  'id, quantity, equipped, equip_slot, rarity, legendary_effect, locked, enchant_level, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal, rolled_extra, items(*)'

export type MaterialInfo = {
  id: string
  key: string
  name: string
  icon: string | null
  material_tier: number
  sell_price: number
}
