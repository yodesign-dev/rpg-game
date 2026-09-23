import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import BottomNav from './BottomNav'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

// Khung chung cho các trang phụ theo phong cách glass của trang nhân vật
export default function GlassPage({
  title,
  subtitle,
  children,
}: {
  title: string
  subtitle?: string
  children: React.ReactNode
}) {
  return (
    <main
      className="min-h-screen text-[#f2ede4] pb-28"
      style={{
        background:
          'radial-gradient(480px 260px at 15% 0%, rgba(107,74,122,.25), transparent 60%),' +
          'radial-gradient(480px 260px at 100% 10%, rgba(224,176,80,.1), transparent 55%),' +
          '#07070a',
      }}
    >
      <div className={`${mono.className} mx-auto max-w-2xl px-4 pt-6`}>
        <div className="mb-6">
          <Link href="/" className="text-sm text-[#a29fb3] hover:text-white">
            ← Về nhân vật
          </Link>
        </div>
        <header className="mb-6">
          <h1 className={`${display.className} text-3xl text-white`}>{title}</h1>
          {subtitle && <p className="text-sm text-[#a29fb3] mt-2">{subtitle}</p>}
        </header>
        {children}
      </div>
      <BottomNav />
    </main>
  )
}
