-- Thương Nhân Bí Ẩn: gacha tiêu vàng ở Chợ.
--
-- x1 = 400 vàng, x10 = 3.600 vàng (chắc chắn ≥ 1 Sử Thi), 1 lượt miễn phí/ngày
-- (giờ VN). Hạng mỗi lượt: Thường 55%, Hiếm 28%, Sử Thi 12%, Huyền Thoại 4.5%,
-- Jackpot 0.5%. Pity: 50 lượt liền không ra Huyền Thoại/Jackpot → lượt thứ 50
-- chắc chắn Huyền Thoại. Phần thưởng theo level nhân vật.
--
-- Chống "in vàng": nguyên liệu tính theo NGÂN SÁCH GIÁ TRỊ (Thường ~100 vàng,
-- Hiếm ~150 + 1 nguyên liệu bậc trên) chia cho giá bán, nên bán lại hết chỉ thu
-- về ~30-75% số vàng bỏ ra (mô phỏng Lv5-72) — gacha luôn là chỗ tiêu vàng.

-- Giá bán đồ theo tier: ×2 → ×1.5 mỗi bậc trên tier gốc (Huyền Thoại ×8 → ×3.4).
-- Với ×2, bán lại toàn bộ đồ gacha ở Lv72 thu về 83% — gần hòa vốn.
create or replace function public.inventory_sell_price(p_sell_price int, p_item_rarity text, p_row_rarity text, p_quantity int)
returns int
language sql
immutable
as $$
  select round(greatest(0, p_sell_price)
          * power(1.5, greatest(0, rarity_rank(coalesce(p_row_rarity, p_item_rarity)) - rarity_rank(p_item_rarity)))
          * greatest(0, p_quantity))::int;
$$;


alter table characters add column if not exists gacha_pity int not null default 0;
alter table characters add column if not exists gacha_free_date date;

create table if not exists gacha_log (
  id           uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  tier         text not null check (tier in ('common', 'rare', 'epic', 'legendary', 'jackpot')),
  item_id      uuid not null references items(id),
  rarity       text not null,
  quantity     int not null,
  created_at   timestamptz not null default clock_timestamp()
);

create index if not exists gacha_log_character_idx on gacha_log(character_id, created_at desc);

alter table gacha_log enable row level security;
drop policy if exists "own gacha_log select" on gacha_log;
create policy "own gacha_log select" on gacha_log
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table gacha_log to authenticated;

alter table activity_feed drop constraint if exists activity_feed_kind_check;
alter table activity_feed add constraint activity_feed_kind_check
  check (kind in ('boss_kill', 'legendary_item', 'title', 'tower', 'gacha_jackpot'));

-- Trang bị ngẫu nhiên hợp level (item_level trong [L-8, L+2]; không có thì gần nhất).
-- p_weapons_only + p_boss_only: Jackpot chỉ lấy vũ khí boss (không bán ở chợ, tier gốc ≥ Hiếm).
create or replace function public.pick_equipment_for_level(p_level int, p_boss_only boolean)
returns uuid
language sql
volatile
set search_path = 'public'
as $$
  select coalesce(
    (select i.id from items i
     where i.type in ('weapon', 'armor')
       and (not p_boss_only or (i.type = 'weapon' and i.buy_price is null and rarity_rank(i.rarity) >= 1))
       and i.item_level between p_level - 8 and p_level + 2
     order by random() limit 1),
    (select i.id from items i
     where i.type in ('weapon', 'armor')
       and (not p_boss_only or (i.type = 'weapon' and i.buy_price is null and rarity_rank(i.rarity) >= 1))
     order by abs(i.item_level - p_level), random() limit 1)
  );
$$;

create or replace function public.gacha_pull(p_character_id uuid, p_count int, p_free boolean)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_gold int; v_pity int; v_free_date date;
  v_count int := case when p_count = 10 then 10 else 1 end;
  v_cost int;
  v_results jsonb := '[]'::jsonb;
  v_has_epic boolean := false;
  v_roll numeric; v_tier text;
  v_item uuid; v_qty int; v_rarity text; v_item2 uuid;
  v_mat uuid; v_mat_price int;
  i int;
begin
  select c.level, c.gold, c.gacha_pity, c.gacha_free_date
    into v_level, v_gold, v_pity, v_free_date
  from characters c where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  if p_free then
    if v_count <> 1 then raise exception 'Lượt miễn phí chỉ mở 1 rương'; end if;
    if v_free_date = vn_today() then raise exception 'Hôm nay đã dùng lượt miễn phí'; end if;
    v_cost := 0;
  else
    v_cost := case when v_count = 10 then 3600 else 400 end;
    if v_gold < v_cost then raise exception 'Không đủ vàng (cần % vàng)', v_cost; end if;
  end if;

  v_mat := material_for_level(v_level);
  select i2.sell_price into v_mat_price from items i2 where i2.id = v_mat;

  for i in 1..v_count loop
    v_pity := v_pity + 1;
    v_roll := random();
    v_tier := case
      when v_roll < 0.005 then 'jackpot'
      when v_roll < 0.05 then 'legendary'
      when v_roll < 0.17 then 'epic'
      when v_roll < 0.45 then 'rare'
      else 'common' end;

    -- Pity: lượt thứ 50 không có Huyền Thoại → ép Huyền Thoại
    if v_pity >= 50 and v_tier not in ('legendary', 'jackpot') then v_tier := 'legendary'; end if;
    -- x10: lượt cuối chưa có Sử Thi nào → ép Sử Thi
    if v_count = 10 and i = 10 and not v_has_epic and v_tier in ('common', 'rare') then v_tier := 'epic'; end if;

    if v_tier in ('epic', 'legendary', 'jackpot') then v_has_epic := true; end if;
    if v_tier in ('legendary', 'jackpot') then v_pity := 0; end if;

    v_item := null; v_item2 := null; v_qty := 1; v_rarity := null;

    if v_tier = 'common' then
      if random() < 0.7 and v_mat is not null then
        v_item := v_mat; v_qty := greatest(1, round(100.0 / greatest(1, v_mat_price))::int);
      else
        select id into v_item from items where key = case
          when v_level < 20 then 'potion_medium' when v_level < 45 then 'potion_large' else 'potion_supreme' end;
        v_qty := case when v_level < 45 then 2 else 1 end;
      end if;
    elsif v_tier = 'rare' then
      if random() < 0.6 and v_mat is not null then
        v_item := v_mat; v_qty := greatest(1, round(150.0 / greatest(1, v_mat_price))::int);
        select id into v_item2 from items where material_tier = (select material_tier + 1 from items where id = v_mat);
      else
        v_item := pick_equipment_for_level(v_level, false); v_rarity := 'rare';
      end if;
    elsif v_tier = 'epic' then
      if random() < 0.75 then
        v_item := pick_equipment_for_level(v_level, false); v_rarity := 'epic';
      else
        select id into v_item from items where key = 'potion_ap_large'; v_qty := 2;
      end if;
    elsif v_tier = 'legendary' then
      v_item := pick_equipment_for_level(v_level, false); v_rarity := 'legendary';
    else
      v_item := pick_equipment_for_level(v_level, true); v_rarity := 'legendary';
    end if;

    if v_item is null then  -- dữ liệu thiếu (vd. chưa có bình) → quy về nguyên liệu
      v_item := v_mat; v_qty := greatest(1, round(100.0 / greatest(1, v_mat_price))::int); v_rarity := null;
    end if;

    -- Trao thưởng: trang bị tạo qua create_equipment (affix + hiệu ứng Huyền
    -- Thoại + bảng tin), vật phẩm gộp chồng qua add_stack
    if v_rarity is not null then
      perform create_equipment(p_character_id, v_item, v_rarity);
    else
      perform add_stack(p_character_id, v_item, v_qty);
    end if;

    insert into gacha_log (character_id, tier, item_id, rarity, quantity)
    values (p_character_id, v_tier, v_item, coalesce(v_rarity, (select rarity from items where id = v_item)), v_qty);

    v_results := v_results || (select jsonb_build_object(
      'tier', v_tier, 'key', it.key, 'name', it.name, 'icon', it.icon,
      'rarity', coalesce(v_rarity, it.rarity), 'qty', v_qty,
      'effect', case when v_rarity = 'legendary' then (
        select inv.legendary_effect from inventory inv
        where inv.character_id = p_character_id and inv.item_id = v_item
        order by inv.acquired_at desc limit 1) end
    ) from items it where it.id = v_item);

    if v_item2 is not null then
      perform add_stack(p_character_id, v_item2, 1);
      v_results := v_results || (select jsonb_build_object(
        'tier', v_tier, 'key', it.key, 'name', it.name, 'icon', it.icon, 'rarity', it.rarity, 'qty', 1
      ) from items it where it.id = v_item2);
    end if;

    if v_tier = 'jackpot' then
      perform post_activity(p_character_id, 'gacha_jackpot', jsonb_build_object(
        'item', (select name from items where id = v_item), 'icon', (select icon from items where id = v_item)
      ));
    end if;
  end loop;

  update characters c
  set gold = c.gold - v_cost,
      gacha_pity = v_pity,
      gacha_free_date = case when p_free then vn_today() else c.gacha_free_date end
  where c.id = p_character_id;

  return jsonb_build_object(
    'results', v_results,
    'gold_left', v_gold - v_cost,
    'pity', v_pity,
    'free_used', p_free
  );
end;
$$;
