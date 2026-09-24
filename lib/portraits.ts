// Chân dung nhân vật: public/portraits/<class>_<1..10>.png — pixel art 64 px đã tách nền
// (pack "500+ Free Pixel-art Fantasy Character Pack" của Batareya). characters.portrait
// null = mẫu 1 của class.
export const PORTRAITS_PER_CLASS = 10

export function portraitKeys(classKey: string) {
  return Array.from({ length: PORTRAITS_PER_CLASS }, (_, i) => `${classKey}_${i + 1}`)
}

export function portraitSrc(classKey: string, portrait: string | null | undefined) {
  const key = portrait && portrait.startsWith(`${classKey}_`) ? portrait : `${classKey}_1`
  return `/portraits/${key}.png`
}

// Quái hình người + NPC dùng chung bộ pixel art. Tra theo tên hiển thị (zone_enemies.name /
// tower_floor_enemies); quái tinh anh ở Tháp có tiền tố "Tinh Anh ".
const ENEMY_PORTRAITS: Record<string, string> = {
  'Pháp Sư Băng': 'enemy_phap_su_bang',
  'Pharaoh Bất Tử': 'enemy_pharaoh_bat_tu',
  'Bóng Ma': 'enemy_bong_ma',
  'Hiệp Sĩ Xương': 'enemy_hiep_si_xuong',
  'Ác Quỷ Vực Sâu': 'enemy_ac_quy_vuc_sau',
  'Chúa Tể Bóng Đêm': 'enemy_chua_te_bong_dem',
  'Thiên Thần Sa Ngã': 'enemy_thien_than_sa_nga',
  'Hiệp Sĩ Thánh Điện': 'enemy_hiep_si_thanh_dien',
  'Thẩm Phán Thánh Quang': 'enemy_tham_phan_thanh_quang',
  'Thợ Săn Hư Vô': 'enemy_tho_san_hu_vo',
  'Hư Vương': 'enemy_hu_vuong',
  'Mẹ Hỗn Nguồn': 'enemy_me_hon_nguon',
  'Thiên Sứ Hộ Vệ': 'enemy_thien_su_ho_ve',
  'Kỵ Sĩ Mây': 'enemy_ky_si_may',
  'Tổng Lãnh Thiên Thần': 'enemy_tong_lanh_thien_than',
  'Đấng Sáng Thế': 'enemy_dang_sang_the',
  'Tinh Linh Cổ Thụ': 'enemy_tinh_linh_co_thu',
}

export function enemyPortraitSrc(name: string) {
  const key = ENEMY_PORTRAITS[name.replace(/^Tinh Anh /, '')]
  return key ? `/portraits/${key}.png` : null
}

export const MERCHANT_PORTRAIT = '/portraits/npc_merchant.png'
