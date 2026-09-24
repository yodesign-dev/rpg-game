import { Alegreya_SC, Be_Vietnam_Pro } from 'next/font/google'

// Font dùng chung — cả hai đều có bộ chữ tiếng Việt (Cinzel/JetBrains Mono cũ thiếu dấu,
// chữ như "Nhiệm Vụ" bị lẫn font dự phòng)
export const display = Alegreya_SC({ subsets: ['latin', 'vietnamese'], weight: ['500', '700'] })
export const ui = Be_Vietnam_Pro({ subsets: ['latin', 'vietnamese'], weight: ['400', '500', '600', '700'] })
