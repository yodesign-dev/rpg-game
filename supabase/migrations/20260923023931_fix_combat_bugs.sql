-- Fix combat bugs in resolve_dungeon_floor:
-- 1. 30-turn stalemate was silently scored as a loss with no explanation
--    even when the character's HP was still full. Adds a `timed_out` flag
--    and an explicit system log entry when the turn limit is hit with both
--    combatants still alive.
-- Return type changed (added `timed_out boolean`), so the function must be
-- dropped before being recreated.

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
  -- Trang bị
  v_weapon_atk int; v_armor_def int;
  -- Skill
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_passive_type text; v_passive_value numeric;
  v_dmg_reduction numeric := 0; v_lifesteal numeric := 0; v_crit_chance numeric := 0;
  -- Tầng / quái
  v_dungeon_id uuid; v_ap_cost int; v_enemy_name text; v_enemy_level int;
  v_enemy_hp int; v_enemy_atk int; v_enemy_def int;
  v_reward_exp int; v_reward_gold int; v_drop_item_id uuid; v_drop_rate numeric; v_drop_item_key text;
  v_is_boss boolean; v_floor_number int;
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

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  if v_current_hp <= 0 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi vào dungeon';
  end if;

  -- 2. Tầng dungeon đang đánh
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

  -- 3. Chỉ số vũ khí/giáp đang trang bị
  select coalesce(sum(i.bonus_atk), 0), coalesce(sum(i.bonus_def), 0)
    into v_weapon_atk, v_armor_def
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and inv.equipped = true;

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
    select leveled_up, new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained);

    if v_drop_item_id is not null and random() < v_drop_rate then
      insert into inventory (character_id, item_id, quantity) values (p_character_id, v_drop_item_id, 1);
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
