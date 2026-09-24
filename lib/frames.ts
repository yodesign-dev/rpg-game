// Khung chân dung (frames pack của Batareya, public/frames/<key>.png) — đồ trang trí mở bằng
// thành tích. Điều kiện phải khớp frame_unlocked() trong DB (guard kiểm tra khi đổi khung).
export type FrameProgress = { level: number; tower_best: number; legendary_found: number; boss_kills: number }

export const FRAMES: { key: string; name: string; hint: string; unlocked: (c: FrameProgress) => boolean }[] = [
  { key: 'wood', name: 'Gỗ Mộc', hint: 'Mặc định', unlocked: () => true },
  { key: 'bronze', name: 'Đồng Thau', hint: 'Đạt cấp 20', unlocked: (c) => c.level >= 20 },
  { key: 'silver', name: 'Bạc Trắng', hint: 'Cấp 40 hoặc qua tầng 30 Tháp', unlocked: (c) => c.level >= 40 || c.tower_best >= 30 },
  { key: 'gold', name: 'Hoàng Kim', hint: 'Cấp 60 hoặc qua tầng 60 Tháp', unlocked: (c) => c.level >= 60 || c.tower_best >= 60 },
  { key: 'bloom', name: 'Hoa Nở', hint: 'Nhặt được đồ Huyền Thoại', unlocked: (c) => c.legendary_found >= 1 },
  { key: 'moss', name: 'Rêu Đá', hint: 'Hạ 50 boss', unlocked: (c) => c.boss_kills >= 50 },
  { key: 'engraved', name: 'Chạm Khắc', hint: 'Chinh phục tầng 100 Tháp', unlocked: (c) => c.tower_best >= 100 },
]

export function frameSrc(frame: string | null | undefined) {
  return `/frames/${FRAMES.some((f) => f.key === frame) ? frame : 'wood'}.png`
}
