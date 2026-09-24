-- Chợ đợt 1 — tiếp tế cho chuyến đi:
-- - Bình máu hồi theo % HP (15/25/35/50%), tự uống trong khám phá / tháp khi HP < 35%,
--   tối đa 3 bình mỗi chuyến (characters.auto_potion bật/tắt). Mô phỏng: 3×35% đưa vùng đúng
--   cấp từ ~52 lên ~93 trận, vùng +10 cấp chỉ ~14 → ~26 (vẫn khó).
-- - Cuộn Tri Thức (+25% EXP, 1/ngày, 500 + 200×cấp vàng), Cuộn May Mắn (+30% rơi đồ, 2/ngày,
--   300 + 80×cấp), Bùa Hộ Mệnh (gục → đứng dậy 50% HP, 1/ngày, 400 + 100×cấp). Dùng từ túi →
--   chờ trong character_buffs, áp vào chuyến khám phá / lần leo tháp kế tiếp rồi mất.
-- - Giá theo cấp (price_per_level), giới hạn ngày (daily_limit + shop_daily, giờ VN).
-- - 5 trang bị thường cấp 1 thôi bán (shop_listed = false).

alter table items add column if not exists heal_pct numeric not null default 0;       -- hồi % HP tối đa
alter table items add column if not exists price_per_level int not null default 0;    -- giá = buy_price + x × cấp
alter table items add column if not exists daily_limit int;                          -- null = không giới hạn
alter table items add column if not exists buff_key text;                            -- exp | luck | guard
alter table items add column if not exists shop_listed boolean not null default true;
alter table characters add column if not exists auto_potion boolean not null default true;

-- Cuộn / bùa đã dùng, chờ áp vào chuyến khám phá hoặc lần leo tháp kế tiếp
create table if not exists character_buffs (
  character_id uuid not null references characters(id) on delete cascade,
  buff_key     text not null,
  created_at   timestamptz not null default now(),
  primary key (character_id, buff_key)
);
alter table character_buffs enable row level security;
drop policy if exists "own buffs select" on character_buffs;
create policy "own buffs select" on character_buffs
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table character_buffs to authenticated;

-- Số lượng đã mua trong ngày (giờ VN) cho món có daily_limit
create table if not exists shop_daily (
  character_id uuid not null references characters(id) on delete cascade,
  item_id      uuid not null references items(id),
  day          date not null,
  qty          int not null default 0,
  primary key (character_id, item_id, day)
);
alter table shop_daily enable row level security;
drop policy if exists "own shop_daily select" on shop_daily;
create policy "own shop_daily select" on shop_daily
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table shop_daily to authenticated;

-- Bình máu hồi theo % HP (không lỗi thời theo cấp), giá nhích theo cấp
update items i set heal_pct = v.pct, price_per_level = v.ppl, description = v.descr
from (values
  ('potion_minor', 0.15, 1, 'Hồi 15% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.'),
  ('potion_medium', 0.25, 2, 'Hồi 25% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.'),
  ('potion_large', 0.35, 4, 'Hồi 35% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.'),
  ('potion_supreme', 0.50, 6, 'Hồi 50% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.')
) as v(key, pct, ppl, descr)
where i.key = v.key;

-- Trang bị thường cấp 1 không còn bán (vô dụng từ cấp 5); đồ đã mua vẫn giữ
update items set shop_listed = false
where key in ('iron_helmet', 'traveler_boots', 'ring_ruby', 'guardian_amulet', 'iron_shield');

insert into items (key, name, type, rarity, buy_price, price_per_level, daily_limit, buff_key, sell_price, description, icon) values
  ('scroll_exp', 'Cuộn Tri Thức', 'consumable', 'epic', 500, 200, 1, 'exp', 0,
   '+25% EXP cho chuyến khám phá / lần leo tháp kế tiếp. Mua tối đa 1 cuộn mỗi ngày.', 'scroll_exp.png'),
  ('scroll_luck', 'Cuộn May Mắn', 'consumable', 'rare', 300, 80, 2, 'luck', 0,
   '+30% tỉ lệ rơi đồ cho chuyến khám phá / lần leo tháp kế tiếp. Mua tối đa 2 cuộn mỗi ngày.', 'scroll_luck.png'),
  ('charm_guard', 'Bùa Hộ Mệnh', 'consumable', 'epic', 400, 100, 1, 'guard', 0,
   'Gục ngã trong chuyến kế tiếp thì đứng dậy với 50% HP và đánh tiếp (1 lần). Mua tối đa 1 bùa mỗi ngày.', 'charm_guard.png')
on conflict (key) do nothing;

-- Uống bình máu mạnh nhất đang có (dùng trong khám phá / tháp). Hết bình → out_name null.
create or replace function public.drink_best_potion(p_character_id uuid, p_hp int, p_max_hp int)
returns table(out_hp int, out_name text)
language plpgsql
set search_path = 'public'
as $$
declare
  v_row record;
begin
  select inv.id as inv_id, inv.quantity as qty, i.name as item_name,
         greatest(coalesce(i.heal_amount, 0), round(p_max_hp * i.heal_pct)::int) as heal
    into v_row
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and i.heal_pct > 0 and inv.quantity > 0
  order by i.heal_pct desc, inv.acquired_at
  limit 1
  for update of inv;

  if v_row.inv_id is null then
    return query select p_hp, null::text;
    return;
  end if;

  if v_row.qty <= 1 then
    delete from inventory where id = v_row.inv_id;
  else
    update inventory set quantity = quantity - 1 where id = v_row.inv_id;
  end if;

  return query select least(p_max_hp, p_hp + v_row.heal), v_row.item_name;
end;
$$;

revoke execute on function public.drink_best_potion(uuid, int, int) from public, anon, authenticated;

create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_current_ap int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_current_hp int; v_current_ap int; v_max_ap int;
  v_max_hp int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int; v_restore_ap int;
  v_heal_pct numeric; v_buff text;
  v_new_hp int; v_new_ap int; v_new_quantity int;
begin
  select user_id into v_owner_user_id from characters where id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select current_hp, current_ap, max_ap
    into v_current_hp, v_current_ap, v_max_ap
  from characters where id = p_character_id for update;

  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  select item_id, quantity into v_item_id, v_quantity
  from inventory where id = p_inventory_id and character_id = p_character_id
  for update;

  if not found then
    raise exception 'Không tìm thấy vật phẩm trong túi đồ';
  end if;

  select type, heal_amount, restore_ap, heal_pct, buff_key into v_type, v_heal_amount, v_restore_ap, v_heal_pct, v_buff
  from items where id = v_item_id;

  -- Bình theo % HP: lấy mức lớn hơn giữa số cố định và % HP tối đa
  v_heal_amount := greatest(coalesce(v_heal_amount, 0), round(v_max_hp * coalesce(v_heal_pct, 0))::int);

  if v_type is distinct from 'consumable'
     or (v_heal_amount <= 0 and coalesce(v_restore_ap, 0) <= 0 and v_buff is null) then
    raise exception 'Vật phẩm này không thể sử dụng';
  end if;

  -- Cuộn / bùa: chờ áp vào chuyến khám phá hoặc lần leo tháp kế tiếp
  if v_buff is not null then
    if exists (select 1 from character_buffs b where b.character_id = p_character_id and b.buff_key = v_buff) then
      raise exception 'Đã có một cuộn/bùa loại này đang chờ dùng';
    end if;
    insert into character_buffs (character_id, buff_key) values (p_character_id, v_buff);
  end if;

  v_new_hp := v_current_hp;
  v_new_ap := v_current_ap;

  if v_buff is null and v_heal_amount > 0 then
    if v_current_hp >= v_max_hp then
      raise exception 'HP đã đầy';
    end if;
    v_new_hp := least(v_max_hp, v_current_hp + v_heal_amount);
  end if;

  if coalesce(v_restore_ap, 0) > 0 then
    if v_current_ap >= v_max_ap then
      raise exception 'AP đã đầy';
    end if;
    v_new_ap := least(v_max_ap, v_current_ap + v_restore_ap);
  end if;

  update characters set current_hp = v_new_hp, current_ap = v_new_ap where id = p_character_id;

  v_new_quantity := v_quantity - 1;

  if v_new_quantity <= 0 then
    delete from inventory where id = p_inventory_id;
  else
    update inventory set quantity = v_new_quantity where id = p_inventory_id;
  end if;

  return query select v_new_hp, v_max_hp, v_new_ap, v_new_quantity;
end;
$$;

create or replace function public.buy_item(p_character_id uuid, p_item_id uuid, p_quantity int default 1)
returns table(new_gold int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_gold int;
  v_buy_price int;
  v_item_type text;
  v_level int; v_per_level int; v_limit int; v_listed boolean; v_bought int;
  v_total_cost int;
  v_inventory_id uuid;
  v_new_quantity int;
begin
  if p_quantity <= 0 then
    raise exception 'Số lượng không hợp lệ';
  end if;

  select user_id, gold into v_owner_user_id, v_gold
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select buy_price, type, price_per_level, daily_limit, shop_listed
    into v_buy_price, v_item_type, v_per_level, v_limit, v_listed
  from items where id = p_item_id;
  select c.level into v_level from characters c where c.id = p_character_id;

  if v_buy_price is null or not v_listed then
    raise exception 'Vật phẩm này không bán trong chợ';
  end if;

  -- Giá tăng theo cấp; món có giới hạn ngày thì đếm theo ngày giờ VN
  v_buy_price := v_buy_price + v_per_level * v_level;
  if v_limit is not null then
    select coalesce(sum(sd.qty), 0) into v_bought from shop_daily sd
    where sd.character_id = p_character_id and sd.item_id = p_item_id and sd.day = vn_today();
    if v_bought + p_quantity > v_limit then
      raise exception 'Hôm nay chỉ được mua tối đa % món này (đã mua %)', v_limit, v_bought;
    end if;
    insert into shop_daily (character_id, item_id, day, qty) values (p_character_id, p_item_id, vn_today(), p_quantity)
    on conflict (character_id, item_id, day) do update set qty = shop_daily.qty + excluded.qty;
  end if;

  v_total_cost := v_buy_price * p_quantity;

  if v_gold < v_total_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_total_cost;
  end if;

  update characters set gold = gold - v_total_cost where id = p_character_id;

  -- Vũ khí/giáp không gộp chồng khi mua (mỗi món 1 dòng riêng), nhất quán
  -- với đồ rơi (luôn tạo dòng mới) — tránh mua thêm 1 bản "vanilla" đè gộp
  -- số lượng lên dòng đã có affix roll từ trước, và giữ đúng equip_slot
  -- theo từng dòng khi mặc nhiều bản cùng key vào các khớp khác nhau.
  if v_item_type in ('weapon', 'armor') then
    insert into inventory (character_id, item_id, quantity)
    values (p_character_id, p_item_id, p_quantity)
    returning quantity into v_new_quantity;
  else
    select id, quantity into v_inventory_id, v_new_quantity
    from inventory where character_id = p_character_id and item_id = p_item_id
    for update;

    if v_inventory_id is null then
      insert into inventory (character_id, item_id, quantity)
      values (p_character_id, p_item_id, p_quantity)
      returning quantity into v_new_quantity;
    else
      update inventory set quantity = quantity + p_quantity
      where id = v_inventory_id
      returning quantity into v_new_quantity;
    end if;
  end if;

  return query select (v_gold - v_total_cost), v_new_quantity;
end;
$$;

create or replace function public.guard_character_game_state()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.level := 1;
      new.exp := 0;
      new.exp_to_next := 100;
      new.gold := 100;
      new.current_chapter := 1;
      new.current_hp := null;
      new.current_ap := 100;
      new.max_ap := 100;
      new.ap_regen_minutes := 1;
      new.last_ap_update := now();
      new.last_hp_update := now();
      new.created_at := now();
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame' - 'auto_potion')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame' - 'auto_potion') then
      raise exception 'Chỉ được đổi tên, chân dung, khung và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    elsif new.frame is distinct from old.frame and new.frame is not null
          and not frame_unlocked(new.frame, new.level, new.tower_best, new.legendary_found, new.boss_kills) then
      raise exception 'Chưa mở khóa khung này';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.explore_zone(p_character_id uuid, p_zone_id uuid, p_turns int)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int;
  v_max_hp int; v_char_atk int; v_char_def int;
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_lifesteal numeric; v_crit_chance numeric;
  v_zone zones%rowtype;
  v_enemy zone_enemies%rowtype;
  v_has_boss boolean;
  v_is_boss boolean;
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  v_win boolean; v_timed_out boolean;
  v_dmg_taken int; v_fight_log jsonb;
  v_effects text[];
  v_last_fight jsonb := null;
  v_hp int;
  v_turn int;
  v_turns_completed int := 0;
  v_wins int := 0;
  v_boss_wins int := 0;
  v_died boolean := false;
  v_fight_exp int; v_fight_gold int;
  v_exp_gained int := 0; v_gold_gained int := 0;
  v_drop record;
  v_drop_rarity text;
  v_fight_drops jsonb;
  v_drop_counts jsonb := '{}'::jsonb;
  v_fights jsonb := '[]'::jsonb;
  v_drops jsonb;
  v_was_full_ap boolean;
  v_leveled_up boolean := false; v_new_level int;
  v_mods jsonb; v_revived boolean;
  -- Tiếp tế: bình tự uống (tối đa 3/chuyến) + cuộn / bùa đang chờ
  v_auto_potion boolean; v_potions_left int := 0; v_potions_used int := 0; v_drink record;
  v_buff_exp boolean := false; v_buff_luck boolean := false; v_buff_guard boolean := false; v_guard_used boolean := false;
begin
  select user_id into v_owner_user_id from characters where id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  p_turns := least(100, greatest(1, coalesce(p_turns, 100)));

  select * into v_zone from zones where id = p_zone_id;
  if not found then raise exception 'Không tìm thấy vùng explore'; end if;

  perform regen_character(p_character_id);

  select level, current_hp, current_ap, max_ap, auto_potion
    into v_level, v_current_hp, v_current_ap, v_max_ap, v_auto_potion
  from characters where id = p_character_id for update;

  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_hp := coalesce(v_current_hp, v_max_hp);

  if v_hp <= 1 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi đi explore';
  end if;

  if v_current_ap < v_zone.ap_cost then
    raise exception 'Không đủ AP để vào vùng này (cần % AP)', v_zone.ap_cost;
  end if;

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;

  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;
  v_effects := get_character_effects(p_character_id);
  v_mods := combat_mods(p_character_id);

  select coalesce(bool_or(b.buff_key = 'exp'), false), coalesce(bool_or(b.buff_key = 'luck'), false),
         coalesce(bool_or(b.buff_key = 'guard'), false)
    into v_buff_exp, v_buff_luck, v_buff_guard
  from character_buffs b where b.character_id = p_character_id;
  delete from character_buffs b where b.character_id = p_character_id;
  v_potions_left := case when v_auto_potion then 3 else 0 end;

  select exists (select 1 from zone_enemies ze where ze.zone_id = p_zone_id and ze.is_boss)
    into v_has_boss;

  for v_turn in 1..p_turns loop
    -- Chọn quái: boss theo boss_chance, còn lại random có trọng số
    -- (Efraimidis–Spirakis: sắp theo -ln(random)/weight, lấy dòng đầu).
    -- Quái cao cấp hơn nhân vật bị giảm trọng số theo (1 + chênh cấp)², nên
    -- ở đầu vùng hiếm gặp con mạnh nhất; vào vùng vượt cấp thì con nào cũng
    -- cao hơn mình nên vẫn khó.
    v_is_boss := v_has_boss and random() < v_zone.boss_chance;

    select * into v_enemy from zone_enemies ze
    where ze.zone_id = p_zone_id and ze.is_boss = v_is_boss
    order by -ln(1 - random())
             / (greatest(1, ze.weight) / power(1 + greatest(0, ze.level - v_level), 2))
    limit 1;

    if not found then raise exception 'Vùng này chưa có quái'; end if;

    select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
    from calculate_combat_scaling(v_level, v_enemy.level);

    select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log, f.out_revived
      into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log, v_revived
    from simulate_fight(
      v_char_atk, v_char_def, v_hp, v_max_hp,
      v_crit_chance, v_lifesteal, v_dmg_reduction,
      v_a1_name, v_a1_power, v_a2_name, v_a2_power,
      v_enemy.name, v_enemy.hp, v_enemy.atk, v_enemy.def,
      v_damage_multiplier, true, v_effects, v_mods,
      v_enemy.level - v_level
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
    -- Giả Chết chỉ 1 lần mỗi chuyến
    if v_revived then v_mods := v_mods - 'revive'; end if;

    v_last_fight := jsonb_build_object(
      'turn', v_turn, 'enemy', v_enemy.name, 'level', v_enemy.level, 'boss', v_is_boss, 'log', v_fight_log
    );

    v_fight_exp := 0; v_fight_gold := 0;
    v_fight_drops := '[]'::jsonb;

    if v_win then
      v_wins := v_wins + 1;
      if v_is_boss then v_boss_wins := v_boss_wins + 1; end if;

      if v_is_boss then
        perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
          'boss', v_enemy.name, 'where', v_zone.icon || ' ' || v_zone.name, 'source', 'explore'
        ));
      end if;
      v_fight_exp := round(v_enemy.reward_exp * v_exp_multiplier * case when v_buff_exp then 1.25 else 1 end);
      v_fight_gold := round(v_enemy.reward_gold * v_exp_multiplier);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate * case when v_buff_luck then 1.3 else 1 end;
        v_drop_rarity := grant_drop(p_character_id, v_drop.item_id, v_is_boss);
        v_fight_drops := v_fight_drops || jsonb_build_object('key', v_drop.key, 'rarity', v_drop_rarity);
        -- Gộp theo cặp item|tier (cùng 1 món có thể rơi ra nhiều tier khác nhau)
        v_drop_counts := jsonb_set(
          v_drop_counts, array[v_drop.key || '|' || v_drop_rarity],
          to_jsonb(coalesce((v_drop_counts ->> (v_drop.key || '|' || v_drop_rarity))::int, 0) + 1)
        );
      end loop;
    end if;

    v_fights := v_fights || jsonb_build_object(
      'turn', v_turn,
      'enemy', v_enemy.name,
      'level', v_enemy.level,
      'boss', v_is_boss,
      'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
      'hp_left', v_hp,
      'dmg_taken', v_dmg_taken,
      'exp', v_fight_exp,
      'gold', v_fight_gold,
      'drops', v_fight_drops
    );

    v_turns_completed := v_turn;

    -- Hết HP: dừng, thưởng chỉ tính các trận đã thắng trước đó
    if not v_win and not v_timed_out then
      if not v_buff_guard then
        v_died := true;
        exit;
      end if;
      -- Bùa Hộ Mệnh: đứng dậy với 50% HP, đánh tiếp chuyến
      v_buff_guard := false;
      v_guard_used := true;
      v_hp := greatest(1, round(v_max_hp * 0.5)::int);
      v_fights := jsonb_set(v_fights, array[(jsonb_array_length(v_fights) - 1)::text, 'guard'], 'true'::jsonb);
    end if;

    -- Tự uống bình khi HP dưới 35%
    if v_potions_left > 0 and v_hp < v_max_hp * 0.35 then
      select d.out_hp, d.out_name into v_drink from drink_best_potion(p_character_id, v_hp, v_max_hp) d;
      if v_drink.out_name is not null then
        v_hp := v_drink.out_hp;
        v_potions_left := v_potions_left - 1;
        v_potions_used := v_potions_used + 1;
        v_fights := jsonb_set(v_fights, array[(jsonb_array_length(v_fights) - 1)::text, 'potion'], to_jsonb(v_drink.out_name));
      else
        v_potions_left := 0;
      end if;
    end if;
  end loop;

  v_was_full_ap := (v_current_ap = v_max_ap);

  update characters
  set current_hp = greatest(1, v_hp),
      current_ap = current_ap - v_zone.ap_cost,
      gold = gold + v_gold_gained,
      last_ap_update = case when v_was_full_ap then now() else last_ap_update end
  where id = p_character_id;

  if v_exp_gained > 0 then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained) as ae;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', dc.drop_rarity,
           'quantity', dc.qty
         ) order by rarity_rank(dc.drop_rarity) desc, i.name), '[]'::jsonb)
    into v_drops
  from (
    select split_part(e.key, '|', 1) as item_key, split_part(e.key, '|', 2) as drop_rarity, e.value::int as qty
    from jsonb_each_text(v_drop_counts) e
  ) dc
  join items i on i.key = dc.item_key;

  -- Bộ đếm thành tích + nhiệm vụ ngày + danh hiệu
  update characters c
  set kills = c.kills + v_wins, boss_kills = c.boss_kills + v_boss_wins
  where c.id = p_character_id;
  perform track_quest(p_character_id, 'kills', v_wins);
  perform track_quest(p_character_id, 'boss', v_boss_wins);
  perform track_quest(p_character_id, 'explore', 1);
  perform award_titles(p_character_id);

  insert into explore_runs (character_id, zone_id, turns_requested, turns_completed, wins, died, exp_gained, gold_gained, drops)
  values (p_character_id, p_zone_id, p_turns, v_turns_completed, v_wins, v_died, v_exp_gained, v_gold_gained, v_drops);

  return jsonb_build_object(
    'zone', v_zone.name,
    'turns_requested', p_turns,
    'turns_completed', v_turns_completed,
    'wins', v_wins,
    'died', v_died,
    'exp_gained', v_exp_gained,
    'gold_gained', v_gold_gained,
    'leveled_up', v_leveled_up,
    'new_level', coalesce(v_new_level, v_level),
    'hp_left', greatest(1, v_hp),
    'max_hp', v_max_hp,
    'ap_left', v_current_ap - v_zone.ap_cost,
    'drops', v_drops,
    'fights', v_fights,
    'last_fight', v_last_fight,
    'potions_used', v_potions_used,
    'guard_used', v_guard_used,
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck)
  );
end;
$$;

create or replace function public.climb_tower(p_character_id uuid, p_start_floor int, p_max_floors int)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  c_ap_per_floor constant int := 5;
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int; v_best int;
  v_max_hp int; v_char_atk int; v_char_def int;
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_lifesteal numeric; v_crit_chance numeric;
  v_effects text[];
  v_hp int; v_ap int;
  v_max int := least(20, greatest(1, coalesce(p_max_floors, 10)));
  v_floor int := p_start_floor;
  v_done int := 0;
  v_stop text := null;
  v_enemy record;
  v_exp_mult numeric; v_dmg_mult numeric;
  v_win boolean; v_timed_out boolean; v_dmg_taken int; v_fight_log jsonb;
  v_last_fight jsonb := null;
  v_enemies jsonb; v_cleared boolean;
  v_floor_exp int; v_floor_gold int; v_floor_kills int; v_floor_bosses int;
  v_first boolean; v_drops jsonb;
  v_mat uuid; v_equip uuid; v_equip_rarity text; v_equip_base text;
  v_floors jsonb := '[]'::jsonb;
  v_exp_total int := 0; v_gold_total int := 0; v_kills int := 0; v_bosses int := 0; v_cleared_count int := 0;
  v_was_full_ap boolean;
  v_leveled_up boolean := false; v_new_level int;
  v_mods jsonb; v_revived boolean;
  v_auto_potion boolean; v_potions_left int := 0; v_potions_used int := 0; v_drink record;
  v_buff_exp boolean := false; v_buff_luck boolean := false; v_buff_guard boolean := false; v_guard_used boolean := false;
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;
  if not found then raise exception 'Không tìm thấy nhân vật'; end if;
  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select c.level, c.current_hp, c.current_ap, c.max_ap, c.tower_best, c.auto_potion
    into v_level, v_current_hp, v_current_ap, v_max_ap, v_best, v_auto_potion
  from characters c where c.id = p_character_id for update;

  if p_start_floor is null or p_start_floor < 1 or p_start_floor > 100
     or (p_start_floor - 1) % 10 <> 0 or p_start_floor - 1 > v_best then
    raise exception 'Chỉ được bắt đầu từ điểm hồi sinh đã mở (tầng 1, 11, 21… tới tầng % )',
      (least(v_best, 99) / 10) * 10 + 1;
  end if;

  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_hp := coalesce(v_current_hp, v_max_hp);
  if v_hp <= 1 then raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi leo tháp'; end if;
  if v_current_ap < c_ap_per_floor then
    raise exception 'Không đủ AP (mỗi tầng cần % AP)', c_ap_per_floor;
  end if;

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power, v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;
  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;
  v_effects := get_character_effects(p_character_id);
  v_mods := combat_mods(p_character_id);

  select coalesce(bool_or(b.buff_key = 'exp'), false), coalesce(bool_or(b.buff_key = 'luck'), false),
         coalesce(bool_or(b.buff_key = 'guard'), false)
    into v_buff_exp, v_buff_luck, v_buff_guard
  from character_buffs b where b.character_id = p_character_id;
  delete from character_buffs b where b.character_id = p_character_id;
  v_potions_left := case when v_auto_potion then 3 else 0 end;

  v_ap := v_current_ap;
  v_was_full_ap := (v_current_ap >= v_max_ap);

  loop
    if v_floor > 100 then v_stop := 'top'; exit; end if;
    if v_done >= v_max then v_stop := 'max_floors'; exit; end if;
    if v_ap < c_ap_per_floor then v_stop := 'no_ap'; exit; end if;

    v_ap := v_ap - c_ap_per_floor;
    v_enemies := '[]'::jsonb;
    v_cleared := true;
    v_floor_exp := 0; v_floor_gold := 0; v_floor_kills := 0; v_floor_bosses := 0;

    for v_enemy in select * from tower_floor_enemies(v_floor) order by out_idx loop
      select sc.exp_multiplier, sc.damage_multiplier into v_exp_mult, v_dmg_mult
      from calculate_combat_scaling(v_level, v_enemy.out_level) sc;

      -- Bùa Hộ Mệnh: gục thì đứng dậy với 50% HP và đánh lại quái này (1 lần mỗi lần leo)
      loop
        select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log, f.out_revived
          into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log, v_revived
        from simulate_fight(
          v_char_atk, v_char_def, v_hp, v_max_hp,
          v_crit_chance, v_lifesteal, v_dmg_reduction,
          v_a1_name, v_a1_power, v_a2_name, v_a2_power,
          v_enemy.out_name, v_enemy.out_hp, v_enemy.out_atk, v_enemy.out_def,
          v_dmg_mult, true, v_effects, v_mods,
          v_enemy.out_level - v_level
        ) f;

        -- Giả Chết chỉ 1 lần mỗi lần leo
        if v_revived then v_mods := v_mods - 'revive'; end if;

        exit when v_win or v_timed_out or not v_buff_guard;
        v_buff_guard := false;
        v_guard_used := true;
        v_hp := greatest(1, round(v_max_hp * 0.5)::int);
      end loop;

      v_last_fight := jsonb_build_object('floor', v_floor, 'enemy', v_enemy.out_name, 'log', v_fight_log);
      v_enemies := v_enemies || jsonb_build_object(
        'name', v_enemy.out_name, 'level', v_enemy.out_level, 'kind', v_enemy.out_kind,
        'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
        'hp_left', v_hp, 'dmg_taken', v_dmg_taken
      );

      if not v_win then
        v_cleared := false;
        v_stop := case when v_timed_out then 'fled' else 'died' end;
        exit;
      end if;

      v_floor_kills := v_floor_kills + 1;
      if v_enemy.out_kind = 'boss' then v_floor_bosses := v_floor_bosses + 1; end if;
      v_floor_exp := v_floor_exp + round(v_enemy.out_exp * v_exp_mult * case when v_buff_exp then 1.25 else 1 end);
      v_floor_gold := v_floor_gold + round(v_enemy.out_gold * v_exp_mult);

      -- Tự uống bình khi HP dưới 35%
      if v_potions_left > 0 and v_hp < v_max_hp * 0.35 then
        select d.out_hp, d.out_name into v_drink from drink_best_potion(p_character_id, v_hp, v_max_hp) d;
        if v_drink.out_name is not null then
          v_hp := v_drink.out_hp;
          v_potions_left := v_potions_left - 1;
          v_potions_used := v_potions_used + 1;
        else
          v_potions_left := 0;
        end if;
      end if;
    end loop;

    -- Quái đã hạ vẫn tính vào thành tích dù tầng trượt; thưởng thì không
    v_kills := v_kills + v_floor_kills;
    v_bosses := v_bosses + v_floor_bosses;
    v_done := v_done + 1;

    if not v_cleared then
      v_floors := v_floors || jsonb_build_object('floor', v_floor, 'cleared', false, 'enemies', v_enemies);
      exit;
    end if;

    v_first := v_floor > v_best;
    v_drops := '[]'::jsonb;

    if v_first then
      v_floor_gold := v_floor_gold + v_floor_gold / 2;
      v_mat := material_for_level(v_floor);
      if v_mat is not null then
        perform add_stack(p_character_id, v_mat, 2);
        v_drops := v_drops || (select jsonb_build_object('key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', i.rarity, 'qty', 2)
                               from items i where i.id = v_mat);
      end if;
    end if;

    -- Tầng boss: lần đầu chắc chắn rơi trang bị, qua lại 20%
    if v_floor % 10 = 0 and (v_first or random() < case when v_buff_luck then 0.26 else 0.2 end) then
      select i.id, i.rarity into v_equip, v_equip_base from items i
      where i.type in ('weapon', 'armor') and i.buy_price is null
        and i.item_level between v_floor - 12 and v_floor + 3
      order by random() limit 1;
      if v_equip is null then
        select i.id, i.rarity into v_equip, v_equip_base from items i
        where i.type in ('weapon', 'armor') and i.buy_price is null
        order by abs(i.item_level - v_floor), random() limit 1;
      end if;
      if v_equip is not null then
        v_equip_rarity := roll_rarity(v_equip_base, 'boss');
        -- tier sàn theo tầng: 30+ ≥ Hiếm, 60+ ≥ Sử Thi, tầng 100 lần đầu = Huyền Thoại
        if v_floor >= 30 and rarity_rank(v_equip_rarity) < 1 then v_equip_rarity := 'rare'; end if;
        if v_floor >= 60 and rarity_rank(v_equip_rarity) < 2 then v_equip_rarity := 'epic'; end if;
        if v_floor = 100 and v_first then v_equip_rarity := 'legendary'; end if;
        perform create_equipment(p_character_id, v_equip, v_equip_rarity);
        v_drops := v_drops || (select jsonb_build_object('key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', v_equip_rarity, 'qty', 1)
                               from items i where i.id = v_equip);
      end if;
      v_equip := null;
    end if;

    if v_first then
      v_best := v_floor;
      if v_floor % 10 = 0 then
        perform post_activity(p_character_id, 'tower', jsonb_build_object('floor', v_floor));
      end if;
    end if;

    v_exp_total := v_exp_total + v_floor_exp;
    v_gold_total := v_gold_total + v_floor_gold;
    v_cleared_count := v_cleared_count + 1;

    v_floors := v_floors || jsonb_build_object(
      'floor', v_floor, 'cleared', true, 'first_clear', v_first,
      'exp', v_floor_exp, 'gold', v_floor_gold, 'drops', v_drops, 'enemies', v_enemies
    );

    -- Nghỉ chân giữa các tầng: hồi 20% HP tối đa
    v_hp := least(v_max_hp, v_hp + ceil(v_max_hp * 0.2)::int);
    v_floor := v_floor + 1;
  end loop;

  update characters c
  set current_hp = greatest(1, v_hp),
      current_ap = v_ap,
      gold = c.gold + v_gold_total,
      tower_best = v_best,
      kills = c.kills + v_kills,
      boss_kills = c.boss_kills + v_bosses,
      last_ap_update = case when v_was_full_ap then now() else c.last_ap_update end
  where c.id = p_character_id;

  if v_exp_total > 0 then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_total) ae;
  end if;

  perform track_quest(p_character_id, 'kills', v_kills);
  perform track_quest(p_character_id, 'boss', v_bosses);
  perform track_quest(p_character_id, 'dungeon', v_cleared_count);
  perform award_titles(p_character_id);

  return jsonb_build_object(
    'start_floor', p_start_floor,
    'floors_attempted', v_done,
    'floors_cleared', v_cleared_count,
    'stop', v_stop,
    'tower_best', v_best,
    'exp_gained', v_exp_total,
    'gold_gained', v_gold_total,
    'leveled_up', v_leveled_up,
    'new_level', coalesce(v_new_level, v_level),
    'hp_left', greatest(1, v_hp),
    'max_hp', v_max_hp,
    'ap_left', v_ap,
    'ap_per_floor', c_ap_per_floor,
    'floors', v_floors,
    'last_fight', v_last_fight,
    'potions_used', v_potions_used,
    'guard_used', v_guard_used,
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck)
  );
end;
$$;
