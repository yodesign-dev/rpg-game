import { enemyPortraitSrc } from './portraits'

// Cấp độ quái: Thường / Tinh Anh / Hung Thần (+ boss riêng). Server gắn cấp vào tên hiển thị
// bằng tiền tố ("Tinh Anh Orc", "Hung Thần Orc") — Tháp và Thám Hiểm dùng chung quy ước.
export type EnemyTier = 'normal' | 'elite' | 'champion' | 'boss'

const TIER_PREFIX: [string, EnemyTier][] = [
  ['Tinh Anh ', 'elite'],
  ['Hung Thần ', 'champion'],
]

export function parseEnemyName(name: string): { base: string; tier: EnemyTier } {
  for (const [prefix, tier] of TIER_PREFIX) if (name.startsWith(prefix)) return { base: name.slice(prefix.length), tier }
  return { base: name, tier: 'normal' }
}

// Quái vật (pack "Free Mythic Monsters", bản Outlined): public/monsters/<họ>_<màu>.png, sprite
// 64 px phóng 3x. Mỗi loài một họ sprite; màu khác của cùng họ dành cho Tinh Anh / Hung Thần.
// [họ, màu thường, màu tinh anh, màu hung thần]
const MONSTERS: Record<string, [string, number, number, number]> = {
  // Rừng Xanh
  'Slime Xanh': ['016', 1, 3, 2],
  'Rắn Cỏ': ['009', 1, 2, 3],
  'Sói Rừng': ['022', 1, 2, 3],
  'Yêu Tinh Rừng': ['024', 1, 3, 2],
  // Đồng Bằng
  'Sâu Đồng': ['003', 1, 3, 5],
  'Bù Nhìn Ma': ['005', 1, 3, 2],
  'Lợn Rừng': ['014', 3, 2, 1],
  'Ong Bắp Cày': ['008', 2, 1, 3],
  'Vua Châu Chấu': ['012', 1, 2, 3],
  // Hang Động
  'Bọ Giáp Hang': ['004', 2, 1, 3],
  'Goblin Thợ Mỏ': ['019', 1, 2, 3],
  'Nhện Hang': ['007', 2, 3, 1],
  Orc: ['023', 2, 3, 1],
  'Ancient Golem': ['001', 1, 3, 2],
  // Núi Tuyết
  'Sói Tuyết': ['022', 3, 2, 1],
  'Hồn Ma Băng': ['006', 1, 3, 2],
  Yeti: ['023', 1, 3, 2],
  'Rồng Băng Non': ['015', 1, 2, 3],
  // Sa Mạc
  'Bọ Cạp Cát': ['001', 2, 3, 1],
  'Rắn Hổ Mang': ['009', 2, 3, 1],
  'Xác Ướp': ['006', 2, 3, 1],
  'Sâu Cát Khổng Lồ': ['003', 2, 4, 5],
  // Núi Lửa
  'Thằn Lằn Lửa': ['017', 1, 3, 2],
  'Tinh Linh Lửa': ['025', 1, 2, 3],
  'Golem Dung Nham': ['011', 1, 3, 2],
  'Chó Địa Ngục': ['026', 1, 3, 2],
  'Rồng Lửa Cổ Đại': ['014', 1, 2, 3],
  // Vực Tối
  'Nhện Bóng Tối': ['007', 1, 3, 2],
  // Thánh Địa
  'Tượng Thần Canh Gác': ['031', 2, 1, 3],
  'Sư Tử Thần': ['027', 1, 2, 3],
  // Hư Không
  'Mắt Hư Không': ['002', 3, 1, 2],
  'Sứa Không Gian': ['010', 1, 3, 2],
  'Kẻ Nuốt Sao': ['013', 1, 3, 2],
  // Cõi Hỗn Nguồn
  'Tinh Thể Sống': ['028', 1, 2, 3],
  'Nguyên Tố Hỗn Mang': ['021', 3, 1, 2],
  'Người Khổng Lồ Pha Lê': ['031', 3, 1, 2],
  'Rồng Nguyên Tố': ['018', 3, 1, 2],
  // Thiên Đường
  'Thiên Nhãn': ['030', 1, 3, 2],
}

export type EnemySprite = { src: string; kind: 'monster' | 'humanoid' }

// Ảnh cho tên hiển thị (có thể kèm tiền tố cấp). Quái hình người chỉ có 1 ảnh — cấp phân biệt
// bằng khung. Không có ảnh → null.
export function enemySprite(name: string): EnemySprite | null {
  const { base, tier } = parseEnemyName(name)
  const m = MONSTERS[base]
  if (m) {
    const [family, normal, elite, champion] = m
    const color = tier === 'elite' ? elite : tier === 'champion' ? champion : normal
    return { src: `/monsters/${family}_${color}.png`, kind: 'monster' }
  }
  const portrait = enemyPortraitSrc(base)
  return portrait ? { src: portrait, kind: 'humanoid' } : null
}

// Đặc tính quái (simulate_fight: p_enemy_traits). Mỗi vùng 1 đặc tính (zones.traits); Tinh Anh
// thêm 1, Hung Thần thêm 2 ngẫu nhiên; boss luôn Cuồng Nộ; Tháp đổi đặc tính mỗi 5 tầng.
export const ENEMY_TRAITS: Record<string, { icon: string; name: string; desc: string }> = {
  armored: { icon: '🛡️', name: 'Giáp Cứng', desc: 'Chí mạng của bạn chỉ còn một nửa sức mạnh, không xuyên giáp' },
  evasive: { icon: '💨', name: 'Né Tránh', desc: '15% đòn đánh của bạn bị trượt' },
  savage: { icon: '🐺', name: 'Hung Bạo', desc: '15% đòn của quái là chí mạng ×1.5' },
  enrage: { icon: '😡', name: 'Cuồng Nộ', desc: 'Dưới 50% HP, quái đánh mạnh hơn 30%' },
  venom: { icon: '🐍', name: 'Độc', desc: 'Trúng đòn bị nhiễm độc: mất 2% HP tối đa mỗi lượt' },
  regen: { icon: '💚', name: 'Tái Sinh', desc: 'Quái hồi 4% HP mỗi lượt (boss 1.5%)' },
  thorny: { icon: '🦔', name: 'Gai', desc: 'Phản lại 4% sát thương bạn gây ra' },
  unholy: { icon: '🕯️', name: 'Ô Uế', desc: 'Hút máu của bạn giảm 50%' },
}
