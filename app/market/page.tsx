import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import MarketManager from './MarketManager'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default async function MarketPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: character } = await supabase
    .from('characters')
    .select('*, classes(*)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!character) redirect('/create-character')

  const { data: items } = await supabase
    .from('items')
    .select('*')
    .not('buy_price', 'is', null)
    .order('buy_price', { ascending: true })

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 py-16">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8">
          <Link href="/" className={`${mono.className} text-xs text-[#8a7f68] hover:text-[#a89b7f]`}>
            ← Về nhân vật
          </Link>
        </div>

        <header className="text-center mb-10">
          <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>Chợ</h1>
          <p className={`${mono.className} text-xs text-[#8a7f68] mt-2`}>
            {character.gold} vàng
          </p>
        </header>

        <MarketManager characterId={character.id} gold={character.gold} items={items ?? []} />
      </div>
    </main>
  )
}
