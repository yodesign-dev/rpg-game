// Pet (migration 20261009100000_pets.sql): bắt quái làm pet khi Thám Hiểm.
// Khớp phía DB: pet_passives (key = khoá mods), pet_catch_rate(), release_pet().

export type PetRarity = 'common' | 'rare' | 'epic' | 'legendary'
export type PetPassive = { key: string; value: number }

export type Pet = {
  id: string
  species: string
  level: number
  rarity: PetRarity
  passives: PetPassive[]
  active: boolean
  caught_at: string
}

export type PetEncounter = {
  id: string
  species: string
  level: number
  rarity: PetRarity
  tries_left: number
  expires_at: string
}

export const PET_RARITY: Record<PetRarity, { label: string; text: string; frame: string }> = {
  common: { label: 'Thường', text: 'text-[#c9c4d4]', frame: 'border-white/20' },
  rare: { label: 'Hiếm', text: 'text-[#8fc4e0]', frame: 'border-[#8fc4e0]/80 shadow-[0_0_6px_rgba(143,196,224,0.45)]' },
  epic: { label: 'Sử Thi', text: 'text-[#d0a8f0]', frame: 'border-[#d0a8f0]/80 shadow-[0_0_8px_rgba(208,168,240,0.5)]' },
  legendary: {
    label: 'Huyền Thoại',
    text: 'text-[#f0c060] font-semibold',
    frame: 'border-[#f0c060] shadow-[0_0_10px_rgba(240,192,96,0.65)]',
  },
}

export const RARITY_ORDER: Record<PetRarity, number> = { legendary: 0, epic: 1, rare: 2, common: 3 }

// Nội tại pet: tên hiển thị + mô tả (giá trị là tỉ lệ 0..1)
export const PET_PASSIVES: Record<string, { icon: string; name: string; label: string; note?: string }> = {
  atk_pct: { icon: '⚔️', name: 'Sức Mạnh', label: 'ATK gốc' },
  def_pct: { icon: '🛡️', name: 'Vững Chãi', label: 'DEF gốc' },
  hp_pct: { icon: '❤️', name: 'Sinh Lực', label: 'HP gốc' },
  crit: { icon: '🎯', name: 'Nhãn Lực', label: 'chí mạng' },
  lifesteal: { icon: '🩸', name: 'Hút Huyết', label: 'hút máu' },
  regen: { icon: '💚', name: 'Tái Tạo', label: 'HP tối đa hồi mỗi lượt' },
  pierce: { icon: '🗡️', name: 'Xuyên Giáp', label: 'xuyên giáp' },
  double: { icon: '⚡', name: 'Liên Kích', label: 'tỉ lệ đánh 2 lần' },
  pet_dmg_red: { icon: '🐢', name: 'Hộ Vệ', label: 'giảm sát thương nhận' },
  exp_pct: { icon: '📘', name: 'Thông Tuệ', label: 'EXP', note: 'khi Thám Hiểm' },
  gold_pct: { icon: '🪙', name: 'Tài Lộc', label: 'vàng', note: 'khi Thám Hiểm' },
  drop_pct: { icon: '🍀', name: 'May Mắn', label: 'tỉ lệ rơi đồ', note: 'khi Thám Hiểm' },
}

export function formatPassive(p: PetPassive) {
  const def = PET_PASSIVES[p.key]
  const pct = `+${(p.value * 100).toFixed(p.value < 0.01 ? 2 : 1)}%`
  if (!def) return { icon: '✨', name: p.key, text: pct }
  return { icon: def.icon, name: def.name, text: `${pct} ${def.label}${def.note ? ` (${def.note})` : ''}` }
}

// Pet đánh theo (migration 20261013100000): mỗi lượt 1 đòn theo % ATK của chủ + 1 skill theo loài,
// hồi 4 lượt. Khớp pet_combat() / pet_species_skills / simulate_fight.
export const PET_ATTACK: Record<PetRarity, { pct: number; power: number }> = {
  common: { pct: 0.08, power: 1 },
  rare: { pct: 0.12, power: 1.25 },
  epic: { pct: 0.18, power: 1.5 },
  legendary: { pct: 0.25, power: 2 },
}

type PetSkillKey = 'heal' | 'guard' | 'bleed' | 'poison' | 'freeze' | 'burn'

export const PET_SKILL_INFO: Record<PetSkillKey, { icon: string; name: string; desc: (power: number) => string }> = {
  heal: { icon: '💚', name: 'Chữa Lành', desc: (p) => `hồi ${Math.round(3 * p)}% HP tối đa khi HP dưới 80%` },
  guard: { icon: '🛡️', name: 'Hộ Thân', desc: () => 'chặn trọn 1 đòn của quái' },
  freeze: { icon: '❄️', name: 'Hơi Băng', desc: (p) => `${Math.round(10 * p)}% đóng băng quái 1 lượt` },
  bleed: { icon: '🩸', name: 'Cắn Xé', desc: (p) => `chảy máu ${Math.round(40 * p)}% đòn pet mỗi lượt × 3` },
  poison: { icon: '🐍', name: 'Phun Độc', desc: (p) => `độc ${Math.round(40 * p)}% đòn pet mỗi lượt × 3` },
  burn: { icon: '🔥', name: 'Phun Lửa', desc: (p) => `thiêu ${Math.round(40 * p)}% đòn pet mỗi lượt × 3` },
}

export const PET_SKILLS: Record<string, PetSkillKey> = {
  'Slime Xanh': 'heal', 'Yêu Tinh Rừng': 'heal', 'Bù Nhìn Ma': 'heal', 'Mắt Hư Không': 'heal',
  'Sứa Không Gian': 'heal', 'Tinh Thể Sống': 'heal', 'Thiên Nhãn': 'heal',
  'Bọ Giáp Hang': 'guard', 'Goblin Thợ Mỏ': 'guard', Orc: 'guard', 'Ancient Golem': 'guard', Yeti: 'guard',
  'Xác Ướp': 'guard', 'Golem Dung Nham': 'guard', 'Tượng Thần Canh Gác': 'guard', 'Người Khổng Lồ Pha Lê': 'guard',
  'Sói Rừng': 'bleed', 'Lợn Rừng': 'bleed', 'Ong Bắp Cày': 'bleed', 'Vua Châu Chấu': 'bleed',
  'Sâu Cát Khổng Lồ': 'bleed', 'Sư Tử Thần': 'bleed', 'Kẻ Nuốt Sao': 'bleed',
  'Rắn Cỏ': 'poison', 'Sâu Đồng': 'poison', 'Nhện Hang': 'poison', 'Bọ Cạp Cát': 'poison',
  'Rắn Hổ Mang': 'poison', 'Nhện Bóng Tối': 'poison', 'Nguyên Tố Hỗn Mang': 'poison',
  'Sói Tuyết': 'freeze', 'Hồn Ma Băng': 'freeze', 'Rồng Băng Non': 'freeze',
  'Thằn Lằn Lửa': 'burn', 'Tinh Linh Lửa': 'burn', 'Chó Địa Ngục': 'burn', 'Rồng Lửa Cổ Đại': 'burn',
  'Rồng Nguyên Tố': 'burn',
}

export function petCombatLine(species: string, rarity: PetRarity) {
  const { pct, power } = PET_ATTACK[rarity]
  const key = PET_SKILLS[species]
  const skill = key ? PET_SKILL_INFO[key] : null
  return {
    attack: `⚔️ Đánh theo ${Math.round(pct * 100)}% ATK mỗi lượt`,
    skill: skill ? `${skill.icon} ${skill.name}: ${skill.desc(power)} (hồi 4 lượt)` : null,
  }
}

// Lưới bắt pet: key item → bậc, khớp pet_catch_rate()
export const NETS = [
  { key: 'net_basic', name: 'Lưới Thường', tier: 1, icon: 'net_basic.png' },
  { key: 'net_good', name: 'Lưới Tốt', tier: 2, icon: 'net_good.png' },
  { key: 'net_master', name: 'Lưới Thượng Hạng', tier: 3, icon: 'net_master.png' },
] as const

const CATCH_RATES: Record<PetRarity, [number, number, number]> = {
  common: [0.6, 0.8, 0.95],
  rare: [0.35, 0.55, 0.75],
  epic: [0.15, 0.3, 0.5],
  legendary: [0.05, 0.12, 0.25],
}

export function catchRate(rarity: PetRarity, tier: number) {
  return CATCH_RATES[rarity][Math.min(3, Math.max(1, tier)) - 1]
}

// Vàng khi thả pet (khớp release_pet)
export function releaseGold(pet: Pick<Pet, 'rarity' | 'level'>) {
  const base = { legendary: 300, epic: 100, rare: 30, common: 10 }[pet.rarity]
  return base * Math.max(1, pet.level)
}

// Sprite: pet Sử Thi / Huyền Thoại dùng màu Tinh Anh / Hung Thần của cùng loài (lib/enemies.ts)
export function petSpriteName(species: string, rarity: PetRarity) {
  return rarity === 'legendary' ? `Hung Thần ${species}` : rarity === 'epic' ? `Tinh Anh ${species}` : species
}
