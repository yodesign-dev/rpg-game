-- Tier riêng cho TỪNG món trang bị (common/rare/epic/legendary).
--
-- Trước đây rarity gắn với loại đồ (items.rarity) nên cùng 1 món luôn ra cùng
-- 1 tier. Giờ inventory.rarity lưu tier của từng món:
-- - Rơi từ explore/dungeon: quái thường 70/22/7/1%, boss 40/35/20/5%
--   (common/rare/epic/legendary). Chế tạo: 60/28/10/2%, hoặc bỏ gấp đôi vàng
--   để quay theo 35/40/20/5%. Không bao giờ thấp hơn items.rarity (tier sàn).
-- - Tier nhân chỉ số gốc ×1.0/1.25/1.6/2.0 và quyết định số dòng affix (1-4,
--   roll_item_affixes có sẵn). Phần nhân chỉ số gốc được cộng vào rolled_*
--   lúc tạo món đồ nên get_character_stats/combat không phải đổi gì.
-- - Mua ở chợ: tier gốc, không affix (rarity để null → UI lấy items.rarity).
-- - Vật phẩm tiêu hao/nguyên liệu không có tier riêng (vẫn gộp chồng).
-- - Đồ đang có: gán tier = items.rarity và cộng phần nhân chỉ số gốc tương
--   ứng (đồ rare/epic cũ mạnh lên một chút).

alter table inventory add column if not exists rarity text
  check (rarity in ('common', 'rare', 'epic', 'legendary'));

-- Thứ tự tier: common < rare < epic < legendary
create or replace function public.rarity_rank(p_rarity text)
returns int
language sql
immutable
as $$
  select case p_rarity when 'legendary' then 3 when 'epic' then 2 when 'rare' then 1 else 0 end;
$$;

-- Hệ số nhân chỉ số gốc (bonus_atk/def/hp của items) theo tier của từng món
create or replace function public.rarity_multiplier(p_rarity text)
returns numeric
language sql
immutable
as $$
  select case p_rarity when 'legendary' then 2.0 when 'epic' then 1.6 when 'rare' then 1.25 else 1.0 end;
$$;

-- Quay tier cho 1 món trang bị. p_table: 'normal' (quái thường), 'boss',
-- 'craft', 'craft_boost' (bỏ gấp đôi vàng). Không bao giờ thấp hơn tier gốc
-- của loại đồ (p_floor = items.rarity), vd. đồ boss rare không ra common.
create or replace function public.roll_rarity(p_floor text, p_table text)
returns text
language plpgsql
volatile
as $$
declare
  v_roll numeric := random();
  v_rarity text;
begin
  -- Ngưỡng cộng dồn [legendary, epic, rare] — phần còn lại là common
  v_rarity := case p_table
    when 'boss' then        case when v_roll < 0.05 then 'legendary' when v_roll < 0.25 then 'epic' when v_roll < 0.60 then 'rare' else 'common' end
    when 'craft' then       case when v_roll < 0.02 then 'legendary' when v_roll < 0.12 then 'epic' when v_roll < 0.40 then 'rare' else 'common' end
    when 'craft_boost' then case when v_roll < 0.05 then 'legendary' when v_roll < 0.25 then 'epic' when v_roll < 0.65 then 'rare' else 'common' end
    else                    case when v_roll < 0.01 then 'legendary' when v_roll < 0.08 then 'epic' when v_roll < 0.30 then 'rare' else 'common' end
  end;

  if rarity_rank(v_rarity) < rarity_rank(coalesce(p_floor, 'common')) then
    v_rarity := p_floor;
  end if;

  return v_rarity;
end;
$$;

-- Tạo 1 món trang bị với tier cho trước: affix roll theo tier + phần chỉ số
-- gốc được nhân theo tier cộng thẳng vào rolled_* — nhờ vậy mọi chỗ đang
-- tính "bonus_* + rolled_*" (get_character_stats, combat, túi đồ) tự đúng.
create or replace function public.create_equipment(p_character_id uuid, p_item_id uuid, p_rarity text)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_slot text; v_school text; v_bonus_atk int; v_bonus_def int; v_bonus_hp int;
  v_mult numeric := rarity_multiplier(p_rarity);
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
begin
  select i.slot, coalesce(i.school, 'physical'), i.bonus_atk, i.bonus_def, i.bonus_hp
    into v_slot, v_school, v_bonus_atk, v_bonus_def, v_bonus_hp
  from items i where i.id = p_item_id;

  select a.roll_atk, a.roll_def, a.roll_hp, a.roll_crit, a.roll_lifesteal
    into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal
  from roll_item_affixes(v_slot, v_school, p_rarity) a;

  insert into inventory (character_id, item_id, quantity, rarity, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal)
  values (
    p_character_id, p_item_id, 1, p_rarity,
    v_roll_atk + round(v_bonus_atk * (v_mult - 1)),
    v_roll_def + round(v_bonus_def * (v_mult - 1)),
    v_roll_hp + round(v_bonus_hp * (v_mult - 1)),
    v_roll_crit, v_roll_lifesteal
  );
end;
$$;

revoke execute on function public.create_equipment(uuid, uuid, text) from public, anon, authenticated;

-- grant_drop đổi kiểu trả về (void → text) và thêm tham số → phải drop trước
drop function if exists public.grant_drop(uuid, uuid);

-- Thêm 1 món đồ rơi vào túi. Trang bị: quay tier (bảng boss nếu p_is_boss)
-- rồi tạo dòng mới. Vật phẩm tiêu hao/nguyên liệu: gộp chồng, giữ tier gốc.
-- Trả về tier thực tế của món vừa nhận.
create or replace function public.grant_drop(p_character_id uuid, p_item_id uuid, p_is_boss boolean default false)
returns text
language plpgsql
set search_path = 'public'
as $$
declare
  v_type text; v_base_rarity text; v_rarity text;
  v_inventory_id uuid;
begin
  select i.type, i.rarity into v_type, v_base_rarity from items i where i.id = p_item_id;

  if v_type in ('weapon', 'armor') then
    v_rarity := roll_rarity(v_base_rarity, case when p_is_boss then 'boss' else 'normal' end);
    perform create_equipment(p_character_id, p_item_id, v_rarity);
    return v_rarity;
  end if;

  select inv.id into v_inventory_id
  from inventory inv where inv.character_id = p_character_id and inv.item_id = p_item_id
  limit 1 for update;

  if v_inventory_id is null then
    insert into inventory (character_id, item_id, quantity) values (p_character_id, p_item_id, 1);
  else
    update inventory set quantity = quantity + 1 where id = v_inventory_id;
  end if;

  return v_base_rarity;
end;
$$;

revoke execute on function public.grant_drop(uuid, uuid, boolean) from public, anon, authenticated;

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
  v_last_fight jsonb := null;
  v_hp int;
  v_turn int;
  v_turns_completed int := 0;
  v_wins int := 0;
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

  select level, current_hp, current_ap, max_ap
    into v_level, v_current_hp, v_current_ap, v_max_ap
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

    select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log
      into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log
    from simulate_fight(
      v_char_atk, v_char_def, v_hp, v_max_hp,
      v_crit_chance, v_lifesteal, v_dmg_reduction,
      v_a1_name, v_a1_power, v_a2_name, v_a2_power,
      v_enemy.name, v_enemy.hp, v_enemy.atk, v_enemy.def,
      v_damage_multiplier, true
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
    v_last_fight := jsonb_build_object(
      'turn', v_turn, 'enemy', v_enemy.name, 'level', v_enemy.level, 'boss', v_is_boss, 'log', v_fight_log
    );

    v_fight_exp := 0; v_fight_gold := 0;
    v_fight_drops := '[]'::jsonb;

    if v_win then
      v_wins := v_wins + 1;
      v_fight_exp := round(v_enemy.reward_exp * v_exp_multiplier);
      v_fight_gold := round(v_enemy.reward_gold * v_exp_multiplier);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate;
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
      v_died := true;
      exit;
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
    'last_fight', v_last_fight
  );
end;
$$;


-- craft_item thêm p_boost + cột result_rarity → phải drop trước
drop function if exists public.craft_item(uuid, uuid);

create or replace function public.craft_item(p_character_id uuid, p_recipe_id uuid, p_boost boolean default false)
returns table(success boolean, result_name text, new_gold int, result_rarity text)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_gold int;
  v_result_item_id uuid; v_result_qty int; v_gold_cost int; v_success_rate numeric;
  v_result_type text;
  v_ing record;
  v_have int;
  v_success boolean;
  v_result_name text;
  v_existing_id uuid; v_existing_qty int;
  v_result_rarity text;
begin
  select user_id, gold into v_owner_user_id, v_gold
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select result_item_id, result_quantity, gold_cost, success_rate
    into v_result_item_id, v_result_qty, v_gold_cost, v_success_rate
  from recipes where id = p_recipe_id;

  if not found then raise exception 'Không tìm thấy công thức'; end if;

  -- Tăng tỉ lệ tier cao: tốn gấp đôi vàng (tối thiểu 50 nếu công thức miễn phí)
  if p_boost then
    v_gold_cost := greatest(50, v_gold_cost * 2);
  end if;

  if v_gold < v_gold_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_gold_cost;
  end if;

  -- Kiểm tra đủ nguyên liệu trước khi trừ bất cứ gì
  for v_ing in
    select ri.item_id, ri.quantity as needed from recipe_ingredients ri where ri.recipe_id = p_recipe_id
  loop
    select coalesce(sum(quantity), 0) into v_have
    from inventory where character_id = p_character_id and item_id = v_ing.item_id;

    if v_have < v_ing.needed then
      raise exception 'Thiếu nguyên liệu để chế tạo';
    end if;
  end loop;

  -- Trừ nguyên liệu — luôn trừ dù thành công hay thất bại (rủi ro thật)
  for v_ing in
    select ri.item_id, ri.quantity as needed from recipe_ingredients ri where ri.recipe_id = p_recipe_id
  loop
    declare
      v_remaining int := v_ing.needed;
      v_row record;
    begin
      for v_row in
        select id, quantity from inventory
        where character_id = p_character_id and item_id = v_ing.item_id
        order by acquired_at
        for update
      loop
        exit when v_remaining <= 0;
        if v_row.quantity <= v_remaining then
          v_remaining := v_remaining - v_row.quantity;
          delete from inventory where id = v_row.id;
        else
          update inventory set quantity = quantity - v_remaining where id = v_row.id;
          v_remaining := 0;
        end if;
      end loop;
    end;
  end loop;

  update characters set gold = gold - v_gold_cost where id = p_character_id;

  v_success := random() < v_success_rate;

  if v_success then
    select type into v_result_type from items where id = v_result_item_id;

    if v_result_type in ('weapon', 'armor') then
      select i.rarity into v_result_rarity from items i where i.id = v_result_item_id;
      v_result_rarity := roll_rarity(v_result_rarity, case when p_boost then 'craft_boost' else 'craft' end);
      for v_n in 1..v_result_qty loop
        perform create_equipment(p_character_id, v_result_item_id, v_result_rarity);
      end loop;
    else
      select id, quantity into v_existing_id, v_existing_qty
      from inventory where character_id = p_character_id and item_id = v_result_item_id
      for update;

      if v_existing_id is null then
        insert into inventory (character_id, item_id, quantity) values (p_character_id, v_result_item_id, v_result_qty);
      else
        update inventory set quantity = quantity + v_result_qty where id = v_existing_id;
      end if;
    end if;

    select name into v_result_name from items where id = v_result_item_id;
  end if;

  return query select v_success, v_result_name, (v_gold - v_gold_cost), v_result_rarity;
end;
$$;


-- Đồ trang bị đang có: gán tier gốc + cộng phần nhân chỉ số gốc theo tier
update inventory inv
set rarity = i.rarity,
    rolled_atk = inv.rolled_atk + round(i.bonus_atk * (rarity_multiplier(i.rarity) - 1)),
    rolled_def = inv.rolled_def + round(i.bonus_def * (rarity_multiplier(i.rarity) - 1)),
    rolled_hp = inv.rolled_hp + round(i.bonus_hp * (rarity_multiplier(i.rarity) - 1))
from items i
where i.id = inv.item_id and i.type in ('weapon', 'armor') and inv.rarity is null
  -- đồ mua ở chợ (chưa từng có affix) giữ nguyên như lúc mua
  and (inv.rolled_atk <> 0 or inv.rolled_def <> 0 or inv.rolled_hp <> 0 or inv.rolled_crit <> 0 or inv.rolled_lifesteal <> 0);
