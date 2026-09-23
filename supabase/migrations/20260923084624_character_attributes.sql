-- Điểm chỉ số STR / INT / AGI / DEX / VIT tự cộng.
--
-- - classes.main_stat: chỉ số duy nhất cộng ATK cho class (warrior=str,
--   mage=int, archer=dex, assassin=agi). VIT (+HP/+DEF) dùng chung mọi class,
--   AGI/DEX cho thêm % chí mạng.
-- - Mỗi cấp +3 điểm (add_experience). Tăng trưởng tự động mỗi cấp của class
--   giảm lại (atk 2→1, def 2→1, hp 8→6) vì phần còn lại giờ đến từ điểm.
-- - Nhân vật đang có được bù (level-1)*3 điểm, tự chia sẵn theo preset của
--   class để không ai bị yếu đi sau migration; lần tẩy điểm đầu miễn phí nên
--   ai muốn build khác thì tẩy lại.
-- - get_character_stats gom công thức HP/ATK/DEF (trước đây chép ở
--   resolve_dungeon_floor, use_item và 3 trang frontend) về một chỗ.

-- 1. Classes -----------------------------------------------------------------
alter table classes
  add column if not exists main_stat text,
  add column if not exists auto_preset jsonb;

update classes set main_stat = 'str', auto_preset = '{"str":2,"vit":1}' where key = 'warrior';
update classes set main_stat = 'int', auto_preset = '{"int":3}'         where key = 'mage';
update classes set main_stat = 'dex', auto_preset = '{"dex":2,"agi":1}' where key = 'archer';
update classes set main_stat = 'agi', auto_preset = '{"agi":2,"dex":1}' where key = 'assassin';

alter table classes
  alter column main_stat set not null,
  alter column auto_preset set not null,
  add constraint classes_main_stat_check check (main_stat in ('str', 'int', 'agi', 'dex'));

update classes set hp_per_level = 6, atk_per_level = 1, def_per_level = 1;
alter table classes
  alter column hp_per_level set default 6,
  alter column atk_per_level set default 1,
  alter column def_per_level set default 1;

-- 2. Characters --------------------------------------------------------------
alter table characters
  add column if not exists stat_points int not null default 0 check (stat_points >= 0),
  add column if not exists stat_str int not null default 0 check (stat_str >= 0),
  add column if not exists stat_int int not null default 0 check (stat_int >= 0),
  add column if not exists stat_agi int not null default 0 check (stat_agi >= 0),
  add column if not exists stat_dex int not null default 0 check (stat_dex >= 0),
  add column if not exists stat_vit int not null default 0 check (stat_vit >= 0),
  add column if not exists auto_allocate_stats boolean not null default false,
  add column if not exists free_stat_reset_used boolean not null default false;

-- 3. Functions ---------------------------------------------------------------
-- ============================================================================
-- ĐIỂM CHỈ SỐ (STR / INT / AGI / DEX / VIT)
-- Mỗi class chỉ có 1 chỉ số chính cộng ATK (classes.main_stat) — vd. Pháp Sư
-- cộng STR không được thêm ATK, nên tự khắc phải dồn INT. VIT là chỉ số phòng
-- thủ dùng chung. Công thức hiệu ứng nằm DUY NHẤT ở attribute_bonuses; bản
-- sao phía client (lib/character-stats.ts) chỉ dùng để xem trước khi cộng.
-- ============================================================================

create or replace function public.attribute_bonuses(
  p_main_stat text, p_str int, p_int int, p_agi int, p_dex int, p_vit int
)
returns table(attr_atk int, attr_def int, attr_hp int, attr_crit numeric)
language sql
immutable
as $$
  select
    -- Chỉ số chính: +1 ATK mỗi điểm
    case p_main_stat
      when 'str' then p_str when 'int' then p_int
      when 'agi' then p_agi when 'dex' then p_dex
      else 0
    end,
    -- VIT: +1 DEF mỗi 2 điểm, +5 HP mỗi điểm
    p_vit / 2,
    p_vit * 5,
    -- AGI +0.5% chí mạng, DEX +0.3% chí mạng (mọi class)
    p_agi * 0.005 + p_dex * 0.003;
$$;

-- Chỉ số tổng hợp của nhân vật: base_* = class + cấp + điểm chỉ số (chưa có
-- trang bị), còn max_hp/atk/def/crit_bonus/lifesteal_bonus = đã cộng trang bị.
-- Dùng chung cho combat, use_item, reset_stats và các trang hiển thị để số
-- trên UI không lệch với số trong trận. security invoker: RLS vẫn áp dụng khi
-- client gọi trực tiếp (chỉ đọc được nhân vật của chính mình).
create or replace function public.get_character_stats(p_character_id uuid)
returns table(
  base_max_hp int, base_atk int, base_def int, base_spd int, attr_crit numeric,
  max_hp int, atk int, def int, crit_bonus numeric, lifesteal_bonus numeric
)
language sql
stable
set search_path = 'public'
as $$
  select
    b.base_max_hp, b.base_atk, b.base_def, b.base_spd, b.attr_crit,
    b.base_max_hp + e.hp, b.base_atk + e.atk, b.base_def + e.def,
    b.attr_crit + e.crit, e.lifesteal
  from (
    select
      cl.base_hp + (ch.level - 1) * cl.hp_per_level + ab.attr_hp as base_max_hp,
      cl.base_atk + (ch.level - 1) * cl.atk_per_level + ab.attr_atk as base_atk,
      cl.base_def + (ch.level - 1) * cl.def_per_level + ab.attr_def as base_def,
      cl.base_spd + (ch.level - 1) * cl.spd_per_level as base_spd,
      ab.attr_crit
    from characters ch
    join classes cl on cl.id = ch.class_id
    cross join lateral attribute_bonuses(
      cl.main_stat, ch.stat_str, ch.stat_int, ch.stat_agi, ch.stat_dex, ch.stat_vit
    ) ab
    where ch.id = p_character_id
  ) b
  cross join lateral (
    select
      coalesce(sum(i.bonus_hp + inv.rolled_hp), 0)::int as hp,
      coalesce(sum(i.bonus_atk + inv.rolled_atk), 0)::int as atk,
      coalesce(sum(i.bonus_def + inv.rolled_def), 0)::int as def,
      coalesce(sum(inv.rolled_crit), 0) as crit,
      coalesce(sum(inv.rolled_lifesteal), 0) as lifesteal
    from inventory inv join items i on i.id = inv.item_id
    where inv.character_id = p_character_id and inv.equipped = true
  ) e;
$$;

-- Chia p_points điểm theo tỉ lệ preset (vd. {"str":2,"vit":1} → str, str,
-- vit, str, str, vit, ...). Preset rỗng thì dồn hết vào VIT.
create or replace function public.split_stat_points(p_points int, p_preset jsonb)
returns table(add_str int, add_int int, add_agi int, add_dex int, add_vit int)
language plpgsql
immutable
as $$
declare
  v_seq text[] := '{}';
  v_key text; v_len int; i int;
  s int := 0; n int := 0; a int := 0; d int := 0; v int := 0;
begin
  foreach v_key in array array['str', 'int', 'agi', 'dex', 'vit'] loop
    for i in 1..coalesce((p_preset ->> v_key)::int, 0) loop
      v_seq := v_seq || v_key;
    end loop;
  end loop;

  v_len := coalesce(array_length(v_seq, 1), 0);
  if v_len = 0 then v_seq := array['vit']; v_len := 1; end if;

  for i in 0..coalesce(p_points, 0) - 1 loop
    case v_seq[(i % v_len) + 1]
      when 'str' then s := s + 1;
      when 'int' then n := n + 1;
      when 'agi' then a := a + 1;
      when 'dex' then d := d + 1;
      else v := v + 1;
    end case;
  end loop;

  return query select s, n, a, d, v;
end;
$$;

-- Người chơi tự cộng điểm (từ panel +/- ở trang nhân vật). Trả về số điểm còn lại.
create or replace function public.allocate_stats(
  p_character_id uuid, p_str int, p_int int, p_agi int, p_dex int, p_vit int
)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_points int;
  v_total int;
begin
  select user_id, stat_points into v_owner_user_id, v_points
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  p_str := coalesce(p_str, 0); p_int := coalesce(p_int, 0); p_agi := coalesce(p_agi, 0);
  p_dex := coalesce(p_dex, 0); p_vit := coalesce(p_vit, 0);

  if least(p_str, p_int, p_agi, p_dex, p_vit) < 0 then
    raise exception 'Số điểm không hợp lệ';
  end if;

  v_total := p_str + p_int + p_agi + p_dex + p_vit;

  if v_total = 0 then raise exception 'Chưa chọn điểm nào để cộng'; end if;
  if v_total > v_points then
    raise exception 'Không đủ điểm chỉ số (còn % điểm)', v_points;
  end if;

  update characters
  set stat_points = stat_points - v_total,
      stat_str = stat_str + p_str, stat_int = stat_int + p_int, stat_agi = stat_agi + p_agi,
      stat_dex = stat_dex + p_dex, stat_vit = stat_vit + p_vit
  where id = p_character_id;

  return v_points - v_total;
end;
$$;

-- Nút "Tự cộng": chia toàn bộ điểm còn lại theo preset của class.
-- Trả về số điểm đã cộng.
create or replace function public.auto_allocate_stats(p_character_id uuid)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_points int;
  v_preset jsonb;
begin
  select c.user_id, c.stat_points, cl.auto_preset into v_owner_user_id, v_points, v_preset
  from characters c join classes cl on cl.id = c.class_id
  where c.id = p_character_id for update of c;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  if v_points <= 0 then raise exception 'Không còn điểm chỉ số để cộng'; end if;

  update characters c
  set stat_points = 0,
      stat_str = c.stat_str + sp.add_str, stat_int = c.stat_int + sp.add_int,
      stat_agi = c.stat_agi + sp.add_agi, stat_dex = c.stat_dex + sp.add_dex,
      stat_vit = c.stat_vit + sp.add_vit
  from split_stat_points(v_points, v_preset) sp
  where c.id = p_character_id;

  return v_points;
end;
$$;

-- Tẩy điểm: trả toàn bộ điểm đã cộng về stat_points. Lần đầu miễn phí, sau đó
-- tốn level × 50 vàng (thêm một chỗ tiêu vàng). HP hiện tại bị kẹp lại nếu
-- vượt HP tối đa mới (vd. vừa tẩy hết VIT). Trả về số vàng đã tốn.
create or replace function public.reset_stats(p_character_id uuid)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_gold int; v_free_used boolean;
  v_spent int; v_cost int;
  v_new_max_hp int;
begin
  select user_id, level, gold, free_stat_reset_used,
         stat_str + stat_int + stat_agi + stat_dex + stat_vit
    into v_owner_user_id, v_level, v_gold, v_free_used, v_spent
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  if v_spent = 0 then raise exception 'Chưa cộng điểm nào để tẩy'; end if;

  v_cost := case when v_free_used then v_level * 50 else 0 end;

  if v_gold < v_cost then
    raise exception 'Không đủ vàng để tẩy điểm (cần % vàng)', v_cost;
  end if;

  update characters
  set gold = gold - v_cost,
      free_stat_reset_used = true,
      stat_points = stat_points + v_spent,
      stat_str = 0, stat_int = 0, stat_agi = 0, stat_dex = 0, stat_vit = 0
  where id = p_character_id;

  select gs.max_hp into v_new_max_hp from get_character_stats(p_character_id) gs;

  update characters
  set current_hp = least(current_hp, v_new_max_hp)
  where id = p_character_id and current_hp is not null;

  return v_cost;
end;
$$;

-- Chặn client tự sửa điểm chỉ số qua REST (RLS "own characters update" cho
-- phép update cả dòng). Các RPC security definer ở trên chạy dưới quyền owner
-- nên current_user không phải 'authenticated' và không bị chặn.
create or replace function public.guard_character_attributes()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.stat_points := 0;
      new.stat_str := 0; new.stat_int := 0; new.stat_agi := 0; new.stat_dex := 0; new.stat_vit := 0;
      new.free_stat_reset_used := false;
    elsif (new.stat_points, new.stat_str, new.stat_int, new.stat_agi, new.stat_dex, new.stat_vit, new.free_stat_reset_used)
          is distinct from
          (old.stat_points, old.stat_str, old.stat_int, old.stat_agi, old.stat_dex, old.stat_vit, old.free_stat_reset_used) then
      raise exception 'Điểm chỉ số chỉ được thay đổi qua cộng/tẩy điểm trong game';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_character_attributes on characters;
create trigger guard_character_attributes
  before insert or update on characters
  for each row execute function public.guard_character_attributes();

create or replace function public.add_experience(p_character_id uuid, p_exp_gained int)
returns table(leveled_up boolean, new_level int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_exp int; v_exp_to_next int;
  v_auto_allocate boolean; v_preset jsonb;
  v_levels_gained int := 0;
begin
  select c.user_id, c.level, c.exp, c.exp_to_next, c.auto_allocate_stats, cl.auto_preset
    into v_owner_user_id, v_level, v_exp, v_exp_to_next, v_auto_allocate, v_preset
  from characters c join classes cl on cl.id = c.class_id
  where c.id = p_character_id for update of c;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  v_exp := v_exp + greatest(0, p_exp_gained);

  while v_exp >= v_exp_to_next loop
    v_exp := v_exp - v_exp_to_next;
    v_level := v_level + 1;
    v_exp_to_next := 100 + (v_level - 1) * 50;
    v_levels_gained := v_levels_gained + 1;
  end loop;

  update characters
  set level = v_level, exp = v_exp, exp_to_next = v_exp_to_next
  where id = p_character_id;

  if v_levels_gained > 0 then
    if v_auto_allocate then
      update characters c
      set stat_str = c.stat_str + sp.add_str, stat_int = c.stat_int + sp.add_int,
          stat_agi = c.stat_agi + sp.add_agi, stat_dex = c.stat_dex + sp.add_dex,
          stat_vit = c.stat_vit + sp.add_vit
      from split_stat_points(v_levels_gained * 3, v_preset) sp
      where c.id = p_character_id;
    else
      update characters
      set stat_points = stat_points + v_levels_gained * 3
      where id = p_character_id;
    end if;
  end if;

  return query select v_levels_gained > 0, v_level;
end;
$$;


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
  -- Chỉ số tổng hợp (class + cấp + điểm chỉ số + trang bị, xem get_character_stats)
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
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

  -- 2. Chỉ số tổng hợp: class + cấp + điểm chỉ số + trang bị (kể cả affix roll)
  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

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

  -- Cộng dồn bonus chí mạng (AGI/DEX + affix) và hút máu (affix) trên nền skill
  -- bị động. Chí mạng chặn ở 75% để AGI dồn cao không thành crit mọi đòn.
  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;

  -- 5. Hệ số scaling theo chênh lệch cấp độ
  select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
  from calculate_combat_scaling(v_level, v_enemy_level);

  -- 6. Mô phỏng trận đấu
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

  -- Hết 30 lượt mà cả hai còn sống: không xác định được thắng thua bằng sát
  -- thương, ghi rõ lý do vào log thay vì báo "Thất bại" mập mờ dù HP còn đầy.
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

  -- 8. Thưởng nếu thắng: EXP (qua hàm add_experience có sẵn), rơi đồ, ghi nhận đã qua tầng
  if v_win then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained) as ae;

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


create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_current_ap int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int; v_class_id uuid;
  v_max_hp int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int; v_restore_ap int;
  v_new_hp int; v_new_ap int; v_new_quantity int;
begin
  select user_id, level, current_hp, current_ap, max_ap, class_id
    into v_owner_user_id, v_level, v_current_hp, v_current_ap, v_max_ap, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  select item_id, quantity into v_item_id, v_quantity
  from inventory where id = p_inventory_id and character_id = p_character_id
  for update;

  if not found then
    raise exception 'Không tìm thấy vật phẩm trong túi đồ';
  end if;

  select type, heal_amount, restore_ap into v_type, v_heal_amount, v_restore_ap
  from items where id = v_item_id;

  if v_type is distinct from 'consumable'
     or (coalesce(v_heal_amount, 0) <= 0 and coalesce(v_restore_ap, 0) <= 0) then
    raise exception 'Vật phẩm này không thể sử dụng';
  end if;

  v_new_hp := v_current_hp;
  v_new_ap := v_current_ap;

  if coalesce(v_heal_amount, 0) > 0 then
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


-- 4. Bù điểm cho nhân vật đang có (chạy dưới quyền owner nên trigger không chặn)
update characters c
set stat_str = x.add_str, stat_int = x.add_int, stat_agi = x.add_agi,
    stat_dex = x.add_dex, stat_vit = x.add_vit
from (
  select ch.id, sp.*
  from characters ch
  join classes cl on cl.id = ch.class_id
  cross join lateral split_stat_points((ch.level - 1) * 3, cl.auto_preset) sp
) x
where x.id = c.id;
