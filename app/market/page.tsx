import { redirect } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import GlassPage, { GoldChip } from '../GlassPage'
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
    <GlassPage title="Chợ" aside={<GoldChip gold={character.gold} />}>
      <div role="tablist" className="flex border-b border-white/10 mb-5">
        {[
          { key: 'shop', label: '🛒 Cửa hàng' },
          { key: 'merchant', label: '🎰 Thương Nhân' },
        ].map((t) => (
          <Link
            key={t.key}
            href={`/market?tab=${t.key}`}
            role="tab"
            aria-selected={tab === t.key}
            className={`flex-1 -mb-px border-b-2 px-2 py-3 text-center text-sm font-medium transition-colors ${
              tab === t.key ? 'text-[#8fe0b0] border-[#8fe0b0]' : 'text-[#a29fb3] border-transparent hover:text-white'
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
    </GlassPage>
  )
}
