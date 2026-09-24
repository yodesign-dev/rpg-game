import Link from 'next/link'
import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage, { GoldChip } from '../GlassPage'
import MarketManager from './MarketManager'
import GachaMerchant, { type GachaHistory } from './GachaMerchant'


export default async function MarketPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { tab: tabParam } = await searchParams
  const tab = tabParam === 'merchant' ? 'merchant' : 'shop'
  const { supabase, character } = await getCurrentCharacter()

  // Lượt miễn phí / giới hạn mua reset theo ngày giờ Việt Nam (khớp vn_today() phía DB)
  const vnToday = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Ho_Chi_Minh' })
  const [{ data: items }, { data: history }, { data: daily }, { data: buffs }] = await Promise.all([
    supabase
      .from('items')
      .select('*')
      .not('buy_price', 'is', null)
      .eq('shop_listed', true)
      .order('buy_price', { ascending: true }),
    supabase
      .from('gacha_log')
      .select('id, tier, rarity, quantity, created_at, item:items(name, icon)')
      .eq('character_id', character.id)
      .order('created_at', { ascending: false })
      .limit(20),
    supabase.from('shop_daily').select('item_id, qty').eq('character_id', character.id).eq('day', vnToday),
    supabase.from('character_buffs').select('buff_key').eq('character_id', character.id),
  ])

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
        <MarketManager
          characterId={character.id}
          gold={character.gold}
          level={character.level}
          items={items ?? []}
          boughtToday={Object.fromEntries((daily ?? []).map((d) => [d.item_id, d.qty]))}
          pendingBuffs={(buffs ?? []).map((b) => b.buff_key)}
        />
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
