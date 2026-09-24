-- Cân bằng lại chiến đấu (áp dụng cho mọi class — cùng đi qua simulate_fight).
--
-- Vấn đề: sát thương quái = max(1, ATK quái − DEF). DEF nhân vật (1/cấp + VIT +
-- đồ, nhân độ hiếm & cường hoá) tăng nhanh hơn ATK quái (1.2/cấp) nên khi mặc đồ
-- đúng cấp, quái ở mọi vùng chỉ gây 1 sát thương/đòn → Lv40 cày được vùng Lv62,
-- cộng EXP ×3 khi vượt cấp nên lên cấp cực nhanh.
--
-- Sửa:
--   1. Quái luôn gây ít nhất 15% ATK của nó: max(ATK − DEF, 15% ATK).
--   2. Nhân vật gây −2% sát thương mỗi cấp thấp hơn quái (thấp nhất 30%) —
--      simulate_fight nhận thêm p_level_gap (mặc định 0: nộm tập, dungeon cũ).
--   3. Thưởng EXP khi vượt cấp tối đa ×1.5 (trước ×3).
-- Mô phỏng (đồ common, Lv40): vùng đúng cấp ~55-75/100 trận, +10 cấp ~20, +20 cấp ~8.

-- 1. EXP khi vượt cấp ----------------------------------------------------------------
create or replace function public.calculate_combat_scaling(p_character_level integer, p_enemy_level integer)
returns table(exp_multiplier numeric, damage_multiplier numeric, level_diff integer)
language sql
immutable
as $$
  select
    -- Mỗi cấp quái cao hơn nhân vật: +15% EXP. Mỗi cấp thấp hơn: -15% EXP.
    -- Chặn trong khoảng [0.2x, 1.5x] — trần cũ 3.0x thưởng quá lớn cho việc vượt cấp.
    greatest(0.2, least(1.5, 1 + (p_enemy_level - p_character_level) * 0.15)) as exp_multiplier,
    -- Mỗi cấp quái cao hơn: +12% sát thương gây ra. Thấp hơn: -12%.
    -- Chặn trong khoảng [0.5x, 2.5x].
    greatest(0.5, least(2.5, 1 + (p_enemy_level - p_character_level) * 0.12)) as damage_multiplier,
    (p_enemy_level - p_character_level) as level_diff;
$$;

-- 2. Công thức sát thương -----------------------------------------------------------
drop function if exists public.simulate_fight(int, int, int, int, numeric, numeric, numeric, text, numeric, text, numeric, text, int, int, int, numeric, boolean, text[], jsonb);

create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean,
  p_effects text[] default '{}',
  p_mods jsonb default '{}',      -- tổng thiên phú (get_talent_totals)
  p_level_gap int default 0       -- cấp quái − cấp nhân vật (> 0: đánh vượt cấp)
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
  v_enemy_dmg numeric; v_enemy_hit int; v_thorns int;
  v_log jsonb := '[]'::jsonb;
  v_win boolean;
  v_timed_out boolean := false;
  v_dmg_taken int := 0;
  v_hits int; v_hit int;
  -- Hiệu ứng Huyền Thoại (đã distinct ở get_character_effects) + thiên phú (p_mods)
  v_double_chance numeric := least(0.5,
    case when 'double_strike' = any(p_effects) then 0.15 else 0 end + coalesce((p_mods->>'double')::numeric, 0));
  v_crit_mult numeric := greatest(case when 'deadly_crit' = any(p_effects) then 2.0 else 1.5 end,
                                  coalesce((p_mods->>'crit_mult')::numeric, 0));
  v_opening_mult numeric := greatest(case when 'opening_strike' = any(p_effects) then 2 else 1 end,
                                     coalesce((p_mods->>'opening')::numeric, 1));
  v_low_hp_ls numeric := greatest(1, coalesce((p_mods->>'low_hp_ls')::numeric, 1));
  v_opening boolean;
  v_guardian numeric := case when 'guardian' = any(p_effects) then 0.88 else 1 end;
  v_thorns_on boolean := 'thorns' = any(p_effects);
  -- Đánh quái cao cấp hơn: −2% sát thương mỗi cấp chênh, thấp nhất còn 30%
  v_gap_mult numeric := greatest(0.3, 1 - greatest(0, p_level_gap) * 0.02);
begin
  while v_char_hp > 0 and v_enemy_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_turn % 2 = 1 then
      v_skill_name := p_a1_name; v_skill_power := p_a1_power;
    else
      v_skill_name := p_a2_name; v_skill_power := p_a2_power;
    end if;

    -- Đòn Kép: đánh thêm 1 đòn trong lượt
    v_hits := case when random() < v_double_chance then 2 else 1 end;

    for v_hit in 1..v_hits loop
      exit when v_enemy_hp <= 0;

      v_base_dmg := greatest(1, (p_char_atk * v_skill_power - p_enemy_def) * v_gap_mult);
      v_opening := v_opening_mult > 1 and v_turn = 1 and v_hit = 1;
      if v_opening then
        v_base_dmg := v_base_dmg * v_opening_mult;   -- Khai Cuộc
      end if;
      v_is_crit := random() < p_crit;
      v_dmg := round(v_base_dmg * (case when v_is_crit then v_crit_mult else 1 end));
      v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

      if p_lifesteal > 0 then
        -- Khát Máu Vô Tận: HP dưới 30% thì hút máu nhân thêm
        v_char_hp := least(p_max_hp, v_char_hp + round(v_dmg * p_lifesteal
          * case when v_char_hp < p_max_hp * 0.3 then v_low_hp_ls else 1 end));
      end if;

      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
          'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp,
          'double', v_hit = 2, 'opening', v_opening
        );
      end if;
    end loop;

    exit when v_enemy_hp <= 0;

    -- DEF trừ thẳng nhưng quái luôn gây ít nhất 15% ATK của nó — trước đây sàn là 1,
    -- DEF nhân vật (cấp + VIT + đồ) vượt ATK quái nên quái gần như không gây sát thương
    v_enemy_dmg := greatest(1, p_enemy_atk - p_char_def, p_enemy_atk * 0.15)
                   * p_damage_multiplier * (1 - p_dmg_reduction) * v_guardian;
    v_enemy_hit := round(v_enemy_dmg);
    v_char_hp := greatest(0, v_char_hp - v_enemy_hit);
    v_dmg_taken := v_dmg_taken + v_enemy_hit;

    -- Phản Đòn: 20% sát thương nhận vào dội lại quái
    v_thorns := case when v_thorns_on then round(v_enemy_hit * 0.2) else 0 end;
    if v_thorns > 0 then
      v_enemy_hp := greatest(0, v_enemy_hp - v_thorns);
    end if;

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
        'damage', v_enemy_hit, 'character_hp_left', v_char_hp,
        'thorns', v_thorns, 'enemy_hp_left', v_enemy_hp
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

-- 3. Khám phá + Tháp truyền chênh lệch cấp --------------------------------------------
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
  v_effects := get_character_effects(p_character_id);

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
      v_damage_multiplier, true, v_effects, get_talent_totals(p_character_id),
      v_enemy.level - v_level
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
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
    'last_fight', v_last_fight
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
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;
  if not found then raise exception 'Không tìm thấy nhân vật'; end if;
  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select c.level, c.current_hp, c.current_ap, c.max_ap, c.tower_best
    into v_level, v_current_hp, v_current_ap, v_max_ap, v_best
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

      select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log
        into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log
      from simulate_fight(
        v_char_atk, v_char_def, v_hp, v_max_hp,
        v_crit_chance, v_lifesteal, v_dmg_reduction,
        v_a1_name, v_a1_power, v_a2_name, v_a2_power,
        v_enemy.out_name, v_enemy.out_hp, v_enemy.out_atk, v_enemy.out_def,
        v_dmg_mult, true, v_effects, get_talent_totals(p_character_id),
        v_enemy.out_level - v_level
      ) f;

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
      v_floor_exp := v_floor_exp + round(v_enemy.out_exp * v_exp_mult);
      v_floor_gold := v_floor_gold + round(v_enemy.out_gold * v_exp_mult);
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
    if v_floor % 10 = 0 and (v_first or random() < 0.2) then
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
    'last_fight', v_last_fight
  );
end;
$$;
