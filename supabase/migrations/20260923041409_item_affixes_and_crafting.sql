-- ============================================================================
-- Part A: random affixes on equipment drops, restricted by weapon "school"
-- ============================================================================
--
-- items.school ('physical' | 'magic') only matters for slot='weapon' — it
-- gates which affix pool a dropped copy of that weapon can roll into, e.g. a
-- sword can never roll the magic-only pool. Everything else defaults
-- 'physical' since only the mage's staff is magic right now.
--
-- Rolled affixes are per-drop, not per-item-template (two drops of the same
-- sword can roll differently), so they live on `inventory` (the instance),
-- not `items` (the template). This only matters for gear that drops from
-- combat — shop purchases stay at fixed template stats (no roll), which is
-- also why buy_item is patched below to stop stacking weapon/armor
-- purchases into one row: a stacked row can't hold two different rolls, and
-- since equip_slot is tracked per-row, stacking also silently broke
-- dual-wielding two of the same weapon key into different arms.

alter table items add column if not exists school text;
update items set school = 'physical' where type = 'weapon' and school is null;
update items set school = 'magic' where key = 'staff_starter';

alter table inventory add column if not exists rolled_atk int not null default 0;
alter table inventory add column if not exists rolled_def int not null default 0;
alter table inventory add column if not exists rolled_hp int not null default 0;
alter table inventory add column if not exists rolled_crit numeric not null default 0;
alter table inventory add column if not exists rolled_lifesteal numeric not null default 0;

create or replace function public.roll_item_affixes(p_slot text, p_school text, p_rarity text)
returns table(roll_atk int, roll_def int, roll_hp int, roll_crit numeric, roll_lifesteal numeric)
language plpgsql
as $$
declare
  v_roll_count int;
  v_flat_min int; v_flat_max int;
  v_pct_min numeric; v_pct_max numeric;
  v_pool text[];
  v_stat text;
  v_atk int := 0; v_def int := 0; v_hp int := 0;
  v_crit numeric := 0; v_lifesteal numeric := 0;
  i int;
begin
  case p_rarity
    when 'legendary' then v_roll_count := 4; v_flat_min := 7; v_flat_max := 12; v_pct_min := 0.05; v_pct_max := 0.10;
    when 'epic'      then v_roll_count := 3; v_flat_min := 4; v_flat_max := 8;  v_pct_min := 0.03; v_pct_max := 0.06;
    when 'rare'      then v_roll_count := 2; v_flat_min := 2; v_flat_max := 5;  v_pct_min := 0.02; v_pct_max := 0.04;
    else                  v_roll_count := 1; v_flat_min := 1; v_flat_max := 3;  v_pct_min := 0.01; v_pct_max := 0.02;
  end case;

  v_pool := case
    when p_slot = 'weapon' and p_school = 'magic' then array['atk', 'lifesteal']
    when p_slot = 'weapon' then array['atk', 'crit', 'lifesteal']
    when p_slot in ('amulet', 'ring') then array['atk', 'def', 'hp', 'crit', 'lifesteal']
    when p_slot in ('shield', 'head', 'chest', 'belt', 'boot') then array['def', 'hp']
    else null
  end;

  if v_pool is null then
    return query select 0, 0, 0, 0::numeric, 0::numeric;
    return;
  end if;

  for i in 1..v_roll_count loop
    v_stat := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
    if v_stat = 'atk' then
      v_atk := v_atk + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'def' then
      v_def := v_def + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'hp' then
      v_hp := v_hp + ((v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1))) * 3)::int;
    elsif v_stat = 'crit' then
      v_crit := v_crit + round((v_pct_min + random() * (v_pct_max - v_pct_min))::numeric, 4);
    elsif v_stat = 'lifesteal' then
      v_lifesteal := v_lifesteal + round((v_pct_min + random() * (v_pct_max - v_pct_min))::numeric, 4);
    end if;
  end loop;

  return query select v_atk, v_def, v_hp, v_crit, v_lifesteal;
end;
$$;

-- resolve_dungeon_floor rewritten to: (1) load equipped-item stats earlier
-- so bonus_hp/rolled_hp can feed into max_hp before it's used, (2) sum
-- rolled_atk/def/hp/crit/lifesteal from equipped inventory rows alongside
-- items.bonus_atk/bonus_def like before, (3) roll affixes on drop.
-- Also fixes a pre-existing gap: armor's bonus_hp was never actually added
-- to max_hp (it only ever showed as text in the UI) — now it is, same as
-- rolled_hp.
drop function if exists public.resolve_dungeon_floor(uuid, uuid);

create or replace function public.resolve_dungeon_floor(p_character_id uuid, p_dungeon_floor_id uuid)
returns table(win boolean, remaining_hp integer, exp_gained integer, gold_gained integer, item_dropped text, leveled_up boolean, new_level integer, combat_log jsonb, timed_out boolean)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  -- Nhân vật
  v_owner_user_id uuid;
  v_level int; v_exp int; v_gold int; v_current_hp int; v_current_ap int; v_max_ap int; v_class_id uuid;
  v_max_hp int;
  -- Class
  v_base_atk int; v_atk_per_level int; v_base_def int; v_def_per_level int;
  v_base_hp int; v_hp_per_level int;
  -- Trang bị (bao gồm cả rolled affix)
  v_weapon_atk int; v_armor_def int; v_item_hp_bonus int; v_item_crit_bonus numeric; v_item_lifesteal_bonus numeric;
  -- Skill
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_passive_type text; v_passive_value numeric;
  v_dmg_reduction numeric := 0; v_lifesteal numeric := 0; v_crit_chance numeric := 0;
  -- Tầng / quái
  v_dungeon_id uuid; v_ap_cost int; v_enemy_name text; v_enemy_level int;
  v_enemy_hp int; v_enemy_atk int; v_enemy_def int;
  v_reward_exp int; v_reward_gold int; v_drop_item_id uuid; v_drop_rate numeric; v_drop_item_key text;
  v_is_boss boolean; v_floor_number int;
  -- Roll đồ rơi
  v_drop_slot text; v_drop_school text; v_drop_rarity text;
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
  -- Scaling
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  -- Vòng lặp trận đấu
  v_char_atk int; v_char_def int;
  v_char_hp int; v_enemy_cur_hp int; v_turn int := 0;
  v_skill_name text; v_skill_power numeric;
  v_base_dmg numeric; v_is_crit boolean; v_dmg int;
  v_enemy_dmg numeric;
  v_log jsonb := '[]'::jsonb;
  v_win boolean;
  v_timed_out boolean := false;
  v_final_hp int;
  v_was_full_ap boolean;
  -- Kết quả cộng dồn
  v_exp_gained int := 0; v_gold_gained int := 0; v_item_dropped text := null;
  v_leveled_up boolean := false; v_new_level int;
begin
  -- 1. Khóa + đọc dữ liệu nhân vật
  select user_id, level, exp, gold, current_hp, current_ap, max_ap, class_id
    into v_owner_user_id, v_level, v_exp, v_gold, v_current_hp, v_current_ap, v_max_ap, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select base_atk, atk_per_level, base_def, def_per_level, base_hp, hp_per_level
    into v_base_atk, v_atk_per_level, v_base_def, v_def_per_level, v_base_hp, v_hp_per_level
  from classes where id = v_class_id;

  -- 2. Chỉ số trang bị đang mặc (kể cả affix roll) — cần trước khi tính max_hp
  select
    coalesce(sum(i.bonus_atk + inv.rolled_atk), 0),
    coalesce(sum(i.bonus_def + inv.rolled_def), 0),
    coalesce(sum(i.bonus_hp + inv.rolled_hp), 0),
    coalesce(sum(inv.rolled_crit), 0),
    coalesce(sum(inv.rolled_lifesteal), 0)
    into v_weapon_atk, v_armor_def, v_item_hp_bonus, v_item_crit_bonus, v_item_lifesteal_bonus
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and inv.equipped = true;

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level + v_item_hp_bonus;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  if v_current_hp <= 0 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi vào dungeon';
  end if;

  -- 3. Tầng dungeon đang đánh
  select df.dungeon_id, df.floor_number, df.is_boss_floor, df.enemy_name, df.enemy_level,
         df.enemy_hp, df.enemy_atk, df.enemy_def, df.reward_exp, df.reward_gold,
         df.drop_item_id, df.drop_rate, d.ap_cost
    into v_dungeon_id, v_floor_number, v_is_boss, v_enemy_name, v_enemy_level,
         v_enemy_hp, v_enemy_atk, v_enemy_def, v_reward_exp, v_reward_gold,
         v_drop_item_id, v_drop_rate, v_ap_cost
  from dungeon_floors df join dungeons d on d.id = df.dungeon_id
  where df.id = p_dungeon_floor_id;

  if not found then raise exception 'Không tìm thấy tầng dungeon'; end if;

  if v_current_ap < v_ap_cost then
    raise exception 'Không đủ AP để vào tầng này (cần % AP)', v_ap_cost;
  end if;

  -- 4. Skill đang trang bị (2 active + tối đa 1 passive)
  select s.name, s.power_multiplier into v_a1_name, v_a1_power
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'active'
  order by s.key limit 1 offset 0;

  select s.name, s.power_multiplier into v_a2_name, v_a2_power
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'active'
  order by s.key limit 1 offset 1;

  if v_a1_name is null then v_a1_name := 'Đánh thường'; v_a1_power := 1.0; end if;
  if v_a2_name is null then v_a2_name := v_a1_name; v_a2_power := v_a1_power; end if;

  select s.effect_type, s.effect_value into v_passive_type, v_passive_value
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'passive'
  limit 1;

  if v_passive_type = 'damage_reduction' then v_dmg_reduction := v_passive_value;
  elsif v_passive_type = 'lifesteal' then v_lifesteal := v_passive_value;
  elsif v_passive_type = 'crit_chance' then v_crit_chance := v_passive_value;
  end if;

  -- Cộng dồn bonus chí mạng/hút máu từ trang bị (affix) vào trên nền skill bị động
  v_crit_chance := v_crit_chance + v_item_crit_bonus;
  v_lifesteal := v_lifesteal + v_item_lifesteal_bonus;

  -- 5. Hệ số scaling theo chênh lệch cấp độ
  select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
  from calculate_combat_scaling(v_level, v_enemy_level);

  -- 6. Mô phỏng trận đấu
  v_char_atk := v_base_atk + (v_level - 1) * v_atk_per_level + v_weapon_atk;
  v_char_def := v_base_def + (v_level - 1) * v_def_per_level + v_armor_def;
  v_char_hp := v_current_hp;
  v_enemy_cur_hp := v_enemy_hp;

  while v_char_hp > 0 and v_enemy_cur_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_turn % 2 = 1 then
      v_skill_name := v_a1_name; v_skill_power := v_a1_power;
    else
      v_skill_name := v_a2_name; v_skill_power := v_a2_power;
    end if;

    v_base_dmg := greatest(1, v_char_atk * v_skill_power - v_enemy_def);
    v_is_crit := random() < v_crit_chance;
    v_dmg := round(v_base_dmg * (case when v_is_crit then 1.5 else 1 end));
    v_enemy_cur_hp := greatest(0, v_enemy_cur_hp - v_dmg);

    if v_lifesteal > 0 then
      v_char_hp := least(v_max_hp, v_char_hp + round(v_dmg * v_lifesteal));
    end if;

    v_log := v_log || jsonb_build_object(
      'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
      'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_cur_hp
    );

    exit when v_enemy_cur_hp <= 0;

    v_enemy_dmg := greatest(1, v_enemy_atk - v_char_def) * v_damage_multiplier * (1 - v_dmg_reduction);
    v_char_hp := greatest(0, v_char_hp - round(v_enemy_dmg));

    v_log := v_log || jsonb_build_object(
      'turn', v_turn, 'actor', 'enemy', 'enemy_name', v_enemy_name,
      'damage', round(v_enemy_dmg), 'character_hp_left', v_char_hp
    );
  end loop;

  v_win := v_enemy_cur_hp <= 0 and v_char_hp > 0;

  if not v_win and v_char_hp > 0 and v_enemy_cur_hp > 0 then
    v_timed_out := true;
    v_log := v_log || jsonb_build_object(
      'turn', v_turn, 'actor', 'system',
      'message', 'Hết giới hạn lượt đánh (30 lượt), buộc phải rút lui'
    );
  end if;

  v_final_hp := case when v_win then v_char_hp else greatest(1, v_char_hp) end;

  -- 7. Trừ AP (luôn trừ, thắng hay thua) — reset mốc hồi AP nếu vừa tiêu từ lúc đầy
  v_was_full_ap := (v_current_ap = v_max_ap);

  if v_win then
    v_exp_gained := round(v_reward_exp * v_exp_multiplier);
    v_gold_gained := round(v_reward_gold * v_exp_multiplier);
  end if;

  update characters
  set current_hp = v_final_hp,
      current_ap = current_ap - v_ap_cost,
      gold = gold + v_gold_gained,
      last_ap_update = case when v_was_full_ap then now() else last_ap_update end
  where id = p_character_id;

  -- 8. Thưởng nếu thắng: EXP (qua hàm add_experience có sẵn), rơi đồ (roll affix), ghi nhận đã qua tầng
  if v_win then
    select leveled_up, new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained);

    if v_drop_item_id is not null and random() < v_drop_rate then
      select slot, coalesce(school, 'physical'), rarity
        into v_drop_slot, v_drop_school, v_drop_rarity
      from items where id = v_drop_item_id;

      select roll_atk, roll_def, roll_hp, roll_crit, roll_lifesteal
        into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal
      from roll_item_affixes(v_drop_slot, v_drop_school, v_drop_rarity);

      insert into inventory (character_id, item_id, quantity, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal)
      values (p_character_id, v_drop_item_id, 1, v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal);

      select key into v_drop_item_key from items where id = v_drop_item_id;
      v_item_dropped := v_drop_item_key;
    end if;

    insert into dungeon_runs (character_id, dungeon_id, current_floor, status, finished_at)
    values (p_character_id, v_dungeon_id, v_floor_number, 'cleared', now());
  end if;

  return query select
    v_win,
    v_final_hp,
    v_exp_gained,
    v_gold_gained,
    v_item_dropped,
    v_leveled_up,
    coalesce(v_new_level, v_level),
    v_log,
    v_timed_out;
end;
$$;

-- buy_item: khoá vũ khí/giáp không gộp chồng khi mua (mỗi món 1 dòng riêng),
-- để nhất quán với đồ rơi (luôn tạo dòng mới) và tránh việc mua thêm 1 bản
-- "vanilla" đè gộp số lượng lên một dòng đã có affix roll từ trước.
drop function if exists public.buy_item(uuid, uuid, int);

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

  select buy_price, type into v_buy_price, v_item_type from items where id = p_item_id;

  if v_buy_price is null then
    raise exception 'Vật phẩm này không bán trong chợ';
  end if;

  v_total_cost := v_buy_price * p_quantity;

  if v_gold < v_total_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_total_cost;
  end if;

  update characters set gold = gold - v_total_cost where id = p_character_id;

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

-- use_item: cộng thêm bonus_hp/rolled_hp từ trang bị đang mặc vào max_hp khi
-- tính giới hạn hồi máu — trước đây chỉ tính base_hp + level, nên nếu có
-- giáp/trang bị cộng HP, người chơi không bao giờ hồi được đến đúng max_hp
-- thật (cái mà resolve_dungeon_floor phía trên đã dùng để giới hạn combat).
drop function if exists public.use_item(uuid, uuid);

create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_class_id uuid;
  v_base_hp int; v_hp_per_level int; v_max_hp int; v_item_hp_bonus int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int;
  v_new_hp int; v_new_quantity int;
begin
  select user_id, level, current_hp, class_id
    into v_owner_user_id, v_level, v_current_hp, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select base_hp, hp_per_level into v_base_hp, v_hp_per_level
  from classes where id = v_class_id;

  select coalesce(sum(i.bonus_hp + inv.rolled_hp), 0) into v_item_hp_bonus
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and inv.equipped = true;

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level + v_item_hp_bonus;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  select item_id, quantity into v_item_id, v_quantity
  from inventory where id = p_inventory_id and character_id = p_character_id
  for update;

  if not found then
    raise exception 'Không tìm thấy vật phẩm trong túi đồ';
  end if;

  select type, heal_amount into v_type, v_heal_amount from items where id = v_item_id;

  if v_type is distinct from 'consumable' or coalesce(v_heal_amount, 0) <= 0 then
    raise exception 'Vật phẩm này không thể sử dụng để hồi máu';
  end if;

  if v_current_hp >= v_max_hp then
    raise exception 'HP đã đầy';
  end if;

  v_new_hp := least(v_max_hp, v_current_hp + v_heal_amount);
  update characters set current_hp = v_new_hp where id = p_character_id;

  v_new_quantity := v_quantity - 1;

  if v_new_quantity <= 0 then
    delete from inventory where id = p_inventory_id;
  else
    update inventory set quantity = v_new_quantity where id = p_inventory_id;
  end if;

  return query select v_new_hp, v_max_hp, v_new_quantity;
end;
$$;

-- ============================================================================
-- Part B: crafting — recipes made of materials, with a % chance to fail
-- ============================================================================
--
-- Materials (wolf_fang, ice_shard, swamp_venom, shadow_ore, void_shard)
-- already drop from their matching dungeons/bosses but had no use anywhere.
-- Recipes below let players craft the existing named boss-drop weapons
-- (forest_blade, frost_blade, cursed_dagger, fortress_greatsword,
-- voidforged_blade) as an alternate, materials-based path instead of
-- relying purely on the boss's own drop_rate. On failure, all consumed
-- materials (and any gold_cost) are lost — the player chose this over a
-- partial refund. Crafted results always come out at the item's fixed
-- template stats (no affix roll) — only dungeon drops roll random affixes.

create table recipes (
  id             uuid primary key default gen_random_uuid(),
  key            text unique not null,
  name           text not null,
  result_item_id uuid not null references items(id),
  result_quantity int not null default 1,
  gold_cost      int not null default 0,
  success_rate   numeric not null default 0.5,  -- 0..1
  description    text
);

create table recipe_ingredients (
  id         uuid primary key default gen_random_uuid(),
  recipe_id  uuid not null references recipes(id) on delete cascade,
  item_id    uuid not null references items(id),
  quantity   int not null default 1,
  unique (recipe_id, item_id)
);

alter table recipes enable row level security;
alter table recipe_ingredients enable row level security;
create policy "public read recipes" on recipes for select using (true);
create policy "public read recipe_ingredients" on recipe_ingredients for select using (true);

insert into recipes (key, name, result_item_id, gold_cost, success_rate, description) values
  ('craft_forest_blade', 'Chế Kiếm Rừng Cổ', (select id from items where key = 'forest_blade'), 0, 0.7, 'Cần 5 Nanh Sói'),
  ('craft_frost_blade', 'Chế Kiếm Băng Giá', (select id from items where key = 'frost_blade'), 0, 0.65, 'Cần 5 Mảnh Băng Vĩnh Cửu'),
  ('craft_cursed_dagger', 'Chế Đoản Đao Nguyền Rủa', (select id from items where key = 'cursed_dagger'), 0, 0.5, 'Cần 5 Nọc Độc Đầm Lầy'),
  ('craft_fortress_greatsword', 'Chế Đại Kiếm Pháo Đài', (select id from items where key = 'fortress_greatsword'), 0, 0.4, 'Cần 5 Quặng Bóng Tối'),
  ('craft_voidforged_blade', 'Chế Thần Kiếm Hư Không', (select id from items where key = 'voidforged_blade'), 100, 0.2, 'Cần 5 Mảnh Vỡ Hư Không + 3 Quặng Bóng Tối')
on conflict (key) do nothing;

insert into recipe_ingredients (recipe_id, item_id, quantity)
select r.id, i.id, ing.qty
from (values
  ('craft_forest_blade', 'wolf_fang', 5),
  ('craft_frost_blade', 'ice_shard', 5),
  ('craft_cursed_dagger', 'swamp_venom', 5),
  ('craft_fortress_greatsword', 'shadow_ore', 5),
  ('craft_voidforged_blade', 'void_shard', 5),
  ('craft_voidforged_blade', 'shadow_ore', 3)
) as ing(recipe_key, item_key, qty)
join recipes r on r.key = ing.recipe_key
join items i on i.key = ing.item_key
on conflict (recipe_id, item_id) do nothing;

create or replace function public.craft_item(p_character_id uuid, p_recipe_id uuid)
returns table(success boolean, result_name text, new_gold int)
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
      insert into inventory (character_id, item_id, quantity) values (p_character_id, v_result_item_id, v_result_qty);
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

  return query select v_success, v_result_name, (v_gold - v_gold_cost);
end;
$$;
