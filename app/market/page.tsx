import { redirect } from 'next/navigation'
import Link from 'next/link'
import { display, ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/server'
import BottomNav from '../BottomNav'
import MarketManager from './MarketManager'
import GachaMerchant, { type GachaHistory } from './GachaMerchant'


export default async function MarketPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { tab: tabParam } = await searchParams
  const tab = tabParam === 'merchant' ? 'merchant' : 'shop'
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

  const [{ data: items }, { data: history }] = await Promise.all([
    supabase.from('items').select('*').not('buy_price', 'is', null).order('buy_price', { ascending: true }),
    supabase
      .from('gacha_log')
      .select('id, tier, rarity, quantity, created_at, item:items(name, icon)')
      .eq('character_id', character.id)
      .order('created_at', { ascending: false })
      .limit(20),
  ])
  // Lượt miễn phí reset theo ngày giờ Việt Nam (khớp vn_today() phía DB)
  const vnToday = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Ho_Chi_Minh' })

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 pt-16 pb-28">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8">
          <Link href="/" className={`${ui.className} text-xs text-[#8a7f68] hover:text-[#a89b7f]`}>
            ← Về nhân vật
          </Link>
        </div>

        <header className="text-center mb-6">
          <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>Chợ</h1>
          <p className={`${ui.className} text-xs text-[#8a7f68] mt-2`}>
            {character.gold} vàng
          </p>
        </header>

        <div role="tablist" className={`${ui.className} grid grid-cols-2 gap-1.5 mb-6`}>
          {[
            { key: 'shop', label: '🛒 Cửa hàng' },
            { key: 'merchant', label: '🎰 Thương Nhân' },
          ].map((t) => (
            <Link
              key={t.key}
              href={`/market?tab=${t.key}`}
              role="tab"
              aria-selected={tab === t.key}
              className={`rounded-sm border px-2 py-2 text-center text-xs ${
                tab === t.key
                  ? 'border-[#8a7f68] bg-[#2c261c] text-[#f1e6c8]'
                  : 'border-[#2c261c] text-[#8a7f68] hover:text-[#a89b7f]'
              }`}
            >
              {t.label}
            </Link>
          ))}
        </div>

        {tab === 'shop' ? (
          <MarketManager characterId={character.id} gold={character.gold} items={items ?? []} />
        ) : (
          <GachaMerchant
            characterId={character.id}
            gold={character.gold}
            pity={character.gacha_pity}
            freeAvailable={character.gacha_free_date !== vnToday}
            history={(history ?? []) as unknown as GachaHistory[]}
          />
        )}
      </div>
      <BottomNav />
    </main>
  )
}
