-- Log chi tiết từng trận: Thám Hiểm (fights[].log) và Tháp (floors[].enemies[].log).
-- simulate_fight vốn đã ghi log mọi trận, trước đây chỉ giữ trận cuối (last_fight — vẫn giữ để
-- tương thích).

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
  -- Cấp quái thường: Tinh Anh / Hung Thần (boss không tung cấp)
  v_tier text; v_tier_roll numeric; v_name text;
  v_e_hp int; v_e_atk int; v_e_def int;
  v_reward_mult numeric; v_drop_mult numeric;
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
  v_ap_spent int; v_pen_gold int := 0; v_pen_exp int := 0;
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
    raise exception 'Không đủ AP để vào vùng này (cần % AP cho 10 trận)', v_zone.ap_cost;
  end if;
  -- Vé AP tính cho mỗi 10 trận: số trận tối đa theo AP đang có
  p_turns := least(p_turns, (v_current_ap / v_zone.ap_cost) * 10);

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
  v_potions_left := case when v_auto_potion then 2 else 0 end;

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

    -- Tung cấp: 2% Hung Thần, 10% Tinh Anh. Tên hiển thị mang tiền tố cấp (web tra ảnh theo tên).
    v_tier := 'normal';
    if not v_is_boss then
      v_tier_roll := random();
      if v_tier_roll < 0.02 then v_tier := 'champion';
      elsif v_tier_roll < 0.12 then v_tier := 'elite';
      end if;
    end if;

    v_name := case v_tier when 'elite' then 'Tinh Anh ' when 'champion' then 'Hung Thần ' else '' end || v_enemy.name;
    v_e_hp := round(v_enemy.hp * case v_tier when 'elite' then 2 when 'champion' then 3 else 1 end);
    v_e_atk := round(v_enemy.atk * case v_tier when 'elite' then 1.15 when 'champion' then 1.3 else 1 end);
    v_e_def := round(v_enemy.def * case v_tier when 'elite' then 1.15 when 'champion' then 1.25 else 1 end);
    v_reward_mult := case v_tier when 'elite' then 2.5 when 'champion' then 4 else 1 end;
    v_drop_mult := case v_tier when 'elite' then 1.5 when 'champion' then 2 else 1 end;

    select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
    from calculate_combat_scaling(v_level, v_enemy.level);

    select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log, f.out_revived
      into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log, v_revived
    from simulate_fight(
      v_char_atk, v_char_def, v_hp, v_max_hp,
      v_crit_chance, v_lifesteal, v_dmg_reduction,
      v_a1_name, v_a1_power, v_a2_name, v_a2_power,
      v_name, v_e_hp, v_e_atk, v_e_def,
      v_damage_multiplier, true, v_effects, v_mods,
      v_enemy.level - v_level
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
    -- Giả Chết chỉ 1 lần mỗi chuyến
    if v_revived then v_mods := v_mods - 'revive'; end if;

    v_last_fight := jsonb_build_object(
      'turn', v_turn, 'enemy', v_name, 'level', v_enemy.level, 'boss', v_is_boss, 'log', v_fight_log
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
      v_fight_exp := round(v_enemy.reward_exp * v_reward_mult * v_exp_multiplier * case when v_buff_exp then 1.25 else 1 end);
      v_fight_gold := round(v_enemy.reward_gold * v_reward_mult * v_exp_multiplier);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate * v_drop_mult * case when v_buff_luck then 1.3 else 1 end;
        -- Hung Thần tung độ hiếm trang bị như boss
        v_drop_rarity := grant_drop(p_character_id, v_drop.item_id, v_is_boss or v_tier = 'champion');
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
      'enemy', v_name,
      'level', v_enemy.level,
      'boss', v_is_boss,
      'tier', v_tier,
      'log', v_fight_log,
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
  v_ap_spent := v_zone.ap_cost * ceil(v_turns_completed / 10.0)::int;

  update characters
  set current_hp = greatest(1, v_hp),
      current_ap = current_ap - v_ap_spent,
      gold = gold + v_gold_gained,
      last_ap_update = case when v_was_full_ap then now() else last_ap_update end
  where id = p_character_id;

  if v_exp_gained > 0 then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained) as ae;
  end if;

  -- Phạt khi gục: mất 10% vàng đang cầm và 15% EXP của cấp hiện tại (không tụt cấp)
  if v_died then
    select floor(c.gold * 0.10)::int, least(c.exp, round(c.exp_to_next * 0.15)::int)
      into v_pen_gold, v_pen_exp
    from characters c where c.id = p_character_id;
    update characters c set gold = c.gold - v_pen_gold, exp = c.exp - v_pen_exp where c.id = p_character_id;
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
    'ap_left', v_current_ap - v_ap_spent,
    'ap_spent', v_ap_spent,
    'penalty', jsonb_build_object('gold', v_pen_gold, 'exp', v_pen_exp),
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
  v_pen_gold int := 0; v_pen_exp int := 0;
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
  v_potions_left := case when v_auto_potion then 2 else 0 end;

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
        'hp_left', v_hp, 'dmg_taken', v_dmg_taken, 'log', v_fight_log
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

  -- Phạt khi gục: mất 10% vàng đang cầm và 15% EXP của cấp hiện tại (không tụt cấp)
  if v_stop = 'died' then
    select floor(c.gold * 0.10)::int, least(c.exp, round(c.exp_to_next * 0.15)::int)
      into v_pen_gold, v_pen_exp
    from characters c where c.id = p_character_id;
    update characters c set gold = c.gold - v_pen_gold, exp = c.exp - v_pen_exp where c.id = p_character_id;
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
    'penalty', jsonb_build_object('gold', v_pen_gold, 'exp', v_pen_exp),
    'floors', v_floors,
    'last_fight', v_last_fight,
    'potions_used', v_potions_used,
    'guard_used', v_guard_used,
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck)
  );
end;
$$;
