-- Log explore chi tiết hơn trên web: mỗi lượt có thêm số máu mất (không
-- suy ra được từ chênh lệch HP vì hút máu hồi lại giữa trận), và trả kèm log
-- từng đòn của trận cuối cùng.
-- simulate_fight đổi kiểu trả về (thêm out_dmg_taken) nên phải drop trước;
-- resolve_dungeon_floor đọc cột theo tên nên không cần tạo lại.

drop function if exists public.simulate_fight(int, int, int, int, numeric, numeric, numeric, text, numeric, text, numeric, text, int, int, int, numeric, boolean);

create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean
)
returns table(out_win boolean, out_timed_out boolean, out_hp_left int, out_dmg_taken int, out_log jsonb)
language plpgsql
volatile
as $$
declare
  v_char_hp int := p_char_hp;
  v_enemy_hp int := p_enemy_hp;
  v_turn int := 0;
  v_skill_name text; v_skill_power numeric;
  v_base_dmg numeric; v_is_crit boolean; v_dmg int;
  v_enemy_dmg numeric;
  v_log jsonb := '[]'::jsonb;
  v_win boolean;
  v_timed_out boolean := false;
  v_dmg_taken int := 0;
begin
  while v_char_hp > 0 and v_enemy_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_turn % 2 = 1 then
      v_skill_name := p_a1_name; v_skill_power := p_a1_power;
    else
      v_skill_name := p_a2_name; v_skill_power := p_a2_power;
    end if;

    v_base_dmg := greatest(1, p_char_atk * v_skill_power - p_enemy_def);
    v_is_crit := random() < p_crit;
    v_dmg := round(v_base_dmg * (case when v_is_crit then 1.5 else 1 end));
    v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

    if p_lifesteal > 0 then
      v_char_hp := least(p_max_hp, v_char_hp + round(v_dmg * p_lifesteal));
    end if;

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
        'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp
      );
    end if;

    exit when v_enemy_hp <= 0;

    v_enemy_dmg := greatest(1, p_enemy_atk - p_char_def) * p_damage_multiplier * (1 - p_dmg_reduction);
    v_char_hp := greatest(0, v_char_hp - round(v_enemy_dmg));
    v_dmg_taken := v_dmg_taken + round(v_enemy_dmg);

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
        'damage', round(v_enemy_dmg), 'character_hp_left', v_char_hp
      );
    end if;
  end loop;

  v_win := v_enemy_hp <= 0 and v_char_hp > 0;

  -- Hết 30 lượt mà cả hai còn sống: không xác định được thắng thua bằng sát
  -- thương, ghi rõ lý do vào log thay vì báo "Thất bại" mập mờ dù HP còn đầy.
  if not v_win and v_char_hp > 0 and v_enemy_hp > 0 then
    v_timed_out := true;
    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'system',
        'message', 'Hết giới hạn lượt đánh (30 lượt), buộc phải rút lui'
      );
    end if;
  end if;

  return query select v_win, v_timed_out, v_char_hp, v_dmg_taken, v_log;
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
  v_last_fight jsonb := null;
  v_hp int;
  v_turn int;
  v_turns_completed int := 0;
  v_wins int := 0;
  v_died boolean := false;
  v_fight_exp int; v_fight_gold int;
  v_exp_gained int := 0; v_gold_gained int := 0;
  v_drop record;
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
        perform grant_drop(p_character_id, v_drop.item_id);
        v_fight_drops := v_fight_drops || to_jsonb(v_drop.key);
        v_drop_counts := jsonb_set(
          v_drop_counts, array[v_drop.key],
          to_jsonb(coalesce((v_drop_counts ->> v_drop.key)::int, 0) + 1)
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
           'key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', i.rarity,
           'quantity', (v_drop_counts ->> i.key)::int
         ) order by i.rarity desc, i.name), '[]'::jsonb)
    into v_drops
  from items i where i.key in (select jsonb_object_keys(v_drop_counts));

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
