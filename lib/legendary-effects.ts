// Hiệu ứng đặc biệt của đồ Huyền Thoại — khóa khớp inventory.legendary_effect,
// logic thật nằm trong simulate_fight (schema.sql). Không cộng dồn: mặc 2 món
// cùng hiệu ứng chỉ tính 1 lần.
export const LEGENDARY_EFFECTS: Record<string, { name: string; description: string }> = {
  double_strike: { name: 'Đòn Kép', description: '15% mỗi lượt đánh thêm 1 đòn' },
  deadly_crit: { name: 'Chí Mạng Chí Tử', description: 'Chí mạng gây ×2.0 thay vì ×1.5' },
  opening_strike: { name: 'Khai Cuộc', description: 'Đòn đầu tiên mỗi trận ×2 sát thương' },
  guardian: { name: 'Hộ Thể', description: 'Giảm 12% sát thương nhận vào' },
  thorns: { name: 'Phản Đòn', description: 'Phản 20% sát thương nhận vào cho quái' },
}
