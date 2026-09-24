-- Trang bị đợt 1 (theo item-design-principles của DautoRPG):
--
-- 1. Ngân sách sức mạnh: dòng phụ có thêm 5 loại tiện ích — xuyên giáp, Đòn Kép, giảm sát
--    thương, hồi HP mỗi lượt, +% sát thương skill (inventory.rolled_extra). Mỗi dòng tiện ích
--    trừ 8% chỉ số gốc của món. Đồ Huyền Thoại: chỉ số gốc ×1.8 (thay ×2.0) vì đã có hiệu ứng.
-- 2. Hiệu lực giảm dần: đóng băng lần 2 trong trận chỉ còn ×0.5 tỉ lệ, tối đa 2 lần/trận
--    (trước đây boss có thể bị khoá lượt liên tục).
-- 3. combat_mods() gộp thiên phú + tiện ích trang bị + bộ kỹ năng cho khám phá / tháp / nộm.
-- Trần: xuyên giáp 100%, Đòn Kép 50%, giảm sát thương từ đồ 25% (chung 60%), hồi 3%/lượt, skill +50%.
-- Chỉ đồ rơi / chế / gacha từ giờ mới có dòng tiện ích; đồ cũ giữ nguyên.

alter table inventory add column if not exists rolled_extra jsonb not null default '{}'::jsonb;

-- 1. Dòng phụ + ngân sách ---------------------------------------------------------------
drop function if exists public.roll_item_affixes(text, text, text);

create or replace function public.roll_item_affixes(p_slot text, p_school text, p_rarity text)
returns table(roll_atk int, roll_def int, roll_hp int, roll_crit numeric, roll_lifesteal numeric, roll_extra jsonb)
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
  v_extra jsonb := '{}'::jsonb;
  v_pct numeric;
  i int;
begin
  case p_rarity
    when 'legendary' then v_roll_count := 4; v_flat_min := 7; v_flat_max := 12; v_pct_min := 0.05; v_pct_max := 0.10;
    when 'epic'      then v_roll_count := 3; v_flat_min := 4; v_flat_max := 8;  v_pct_min := 0.03; v_pct_max := 0.06;
    when 'rare'      then v_roll_count := 2; v_flat_min := 2; v_flat_max := 5;  v_pct_min := 0.02; v_pct_max := 0.04;
    else                  v_roll_count := 1; v_flat_min := 1; v_flat_max := 3;  v_pct_min := 0.01; v_pct_max := 0.02;
  end case;

  -- Dòng tiện ích (pierce, double, dmg_red, regen, skill_dmg) chiếm ~1/3 pool; chỉ số thô
  -- lặp 2 lần để vẫn là dòng hay gặp nhất
  v_pool := case
    when p_slot = 'weapon' and p_school = 'magic' then
      array['atk', 'atk', 'lifesteal', 'pierce', 'skill_dmg']
    when p_slot = 'weapon' then
      array['atk', 'atk', 'crit', 'crit', 'lifesteal', 'pierce', 'double', 'skill_dmg']
    when p_slot in ('amulet', 'ring') then
      array['atk', 'def', 'hp', 'crit', 'lifesteal', 'atk', 'hp', 'crit', 'double', 'skill_dmg', 'regen']
    when p_slot in ('shield', 'head', 'chest', 'belt', 'boot') then
      array['def', 'hp', 'def', 'hp', 'dmg_red', 'regen']
    else null
  end;

  if v_pool is null then
    return query select 0, 0, 0, 0::numeric, 0::numeric, '{}'::jsonb;
    return;
  end if;

  for i in 1..v_roll_count loop
    v_stat := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
    -- Mỗi dòng tiện ích tối đa 1 lần / món; trùng thì thành chỉ số thô đầu pool
    if v_extra ? v_stat then v_stat := v_pool[1]; end if;
    v_pct := v_pct_min + random() * (v_pct_max - v_pct_min);
    if v_stat = 'atk' then
      v_atk := v_atk + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'def' then
      v_def := v_def + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'hp' then
      v_hp := v_hp + ((v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1))) * 3)::int;
    elsif v_stat = 'crit' then
      v_crit := v_crit + round(v_pct::numeric, 4);
    elsif v_stat = 'lifesteal' then
      v_lifesteal := v_lifesteal + round(v_pct::numeric, 4);
    else
      -- Tiện ích: pierce/skill_dmg ×2, double/dmg_red ×0.8, regen ×0.15 so với dải % của tier
      v_pct := round((v_pct * case v_stat when 'pierce' then 2 when 'skill_dmg' then 2
                                          when 'regen' then 0.15 else 0.8 end)::numeric, 4);
      v_extra := jsonb_set(v_extra, array[v_stat],
        to_jsonb(coalesce((v_extra->>v_stat)::numeric, 0) + v_pct));
    end if;
  end loop;

  return query select v_atk, v_def, v_hp, v_crit, v_lifesteal, v_extra;
end;
$$;

create or replace function public.rarity_multiplier(p_rarity text)
returns numeric
language sql
immutable
as $$
  select case p_rarity when 'legendary' then 1.8 when 'epic' then 1.6 when 'rare' then 1.25 else 1.0 end;
$$;

create or replace function public.create_equipment(p_character_id uuid, p_item_id uuid, p_rarity text)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_slot text; v_school text; v_bonus_atk int; v_bonus_def int; v_bonus_hp int;
  v_mult numeric := rarity_multiplier(p_rarity);
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
  v_roll_extra jsonb; v_utility int;
  v_effect text;
  v_item_name text; v_item_key text; v_item_icon text;
begin
  select i.slot, coalesce(i.school, 'physical'), i.bonus_atk, i.bonus_def, i.bonus_hp
    into v_slot, v_school, v_bonus_atk, v_bonus_def, v_bonus_hp
  from items i where i.id = p_item_id;

  select a.roll_atk, a.roll_def, a.roll_hp, a.roll_crit, a.roll_lifesteal, a.roll_extra
    into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal, v_roll_extra
  from roll_item_affixes(v_slot, v_school, p_rarity) a;

  -- Ngân sách sức mạnh: mỗi dòng tiện ích trừ 8% chỉ số gốc của món
  select count(*) into v_utility from jsonb_object_keys(v_roll_extra);
  v_mult := v_mult - 0.08 * v_utility;

  if p_rarity = 'legendary' then
    v_effect := roll_legendary_effect();
  end if;

  insert into inventory (character_id, item_id, quantity, rarity, legendary_effect, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal, rolled_extra)
  values (
    p_character_id, p_item_id, 1, p_rarity, v_effect,
    v_roll_atk + round(v_bonus_atk * (v_mult - 1)),
    v_roll_def + round(v_bonus_def * (v_mult - 1)),
    v_roll_hp + round(v_bonus_hp * (v_mult - 1)),
    v_roll_crit, v_roll_lifesteal, v_roll_extra
  );

  -- Đồ Huyền Thoại (rơi hoặc chế tạo) lên bảng tin + đếm cho danh hiệu
  if p_rarity = 'legendary' then
    update characters c set legendary_found = c.legendary_found + 1 where c.id = p_character_id;
    select i.name, i.key, i.icon into v_item_name, v_item_key, v_item_icon from items i where i.id = p_item_id;
    perform post_activity(p_character_id, 'legendary_item', jsonb_build_object(
      'item', v_item_name, 'item_key', v_item_key, 'icon', v_item_icon, 'effect', v_effect
    ));
    perform award_titles(p_character_id);
  end if;
end;
$$;

create or replace function public.inventory_item_score(p_inventory_id uuid)
returns numeric
language sql
stable
set search_path = 'public'
as $$
  select (i.bonus_atk + inv.rolled_atk) * 2
       + (i.bonus_def + inv.rolled_def) * 1.5
       + (i.bonus_hp + inv.rolled_hp) * 0.25
       + (inv.rolled_crit + inv.rolled_lifesteal) * 400
       + coalesce((inv.rolled_extra->>'pierce')::numeric, 0) * 150
       + coalesce((inv.rolled_extra->>'double')::numeric, 0) * 300
       + coalesce((inv.rolled_extra->>'dmg_red')::numeric, 0) * 500
       + coalesce((inv.rolled_extra->>'regen')::numeric, 0) * 800
       + coalesce((inv.rolled_extra->>'skill_dmg')::numeric, 0) * 200
       + case when inv.legendary_effect is not null then 60 else 0 end
  from inventory inv join items i on i.id = inv.item_id
  where inv.id = p_inventory_id;
$$;

-- 2. Gộp chỉ số cho vòng đánh -----------------------------------------------------------
-- Tổng dòng tiện ích của đồ đang mặc
create or replace function public.get_gear_mods(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = 'public'
as $$
  select coalesce(jsonb_object_agg(e.key, e.total), '{}'::jsonb)
  from (
    select x.key, sum(x.value::text::numeric) as total
    from inventory inv cross join lateral jsonb_each(inv.rolled_extra) x
    where inv.character_id = p_character_id and inv.equipped
    group by x.key
  ) e;
$$;

-- Mọi thứ vòng đánh cần ngoài chỉ số: thiên phú + dòng tiện ích trang bị (cộng dồn) + bộ kỹ năng.
-- dmg_red của đồ đi riêng (gear_dmg_red) vì dmg_red thiên phú đã gộp ở get_combat_skills.
create or replace function public.combat_mods(p_character_id uuid)
returns jsonb
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v jsonb := get_talent_totals(p_character_id);
  g jsonb := get_gear_mods(p_character_id);
  k text;
begin
  for k in select jsonb_object_keys(g) loop
    if k = 'dmg_red' then
      v := v || jsonb_build_object('gear_dmg_red', (g->>k)::numeric);
    else
      v := v || jsonb_build_object(k, coalesce((v->>k)::numeric, 0) + (g->>k)::numeric);
    end if;
  end loop;
  return v || jsonb_build_object('kit', get_skill_kit(p_character_id));
end;
$$;

-- 3. Vòng đánh -------------------------------------------------------------------------
create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean,
  p_effects text[] default '{}',
  p_mods jsonb default '{}',      -- tổng thiên phú (get_talent_totals) + 'kit' (get_skill_kit)
  p_level_gap int default 0       -- cấp quái − cấp nhân vật (> 0: đánh vượt cấp)
)
returns table(out_win boolean, out_timed_out boolean, out_hp_left int, out_dmg_taken int, out_log jsonb,
              out_revived boolean)
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
  -- Ô thiên phú lấy cảm hứng từ DautoRPG
  v_rage numeric := coalesce((p_mods->>'rage')::numeric, 0);              -- Cuồng Huyết
  v_guard_step numeric := coalesce((p_mods->>'guard_stack')::numeric, 0); -- Trụ Cột
  v_guard_hits int := 0;
  v_prestige numeric := coalesce((p_mods->>'prestige')::numeric, 0);      -- Phong Hầu
  v_parry numeric := least(0.5, coalesce((p_mods->>'parry')::numeric, 0)); -- Phản Kích
  v_parry_mult numeric := coalesce((p_mods->>'parry_mult')::numeric, 1.5);
  v_echo numeric := least(0.5, coalesce((p_mods->>'echo')::numeric, 0));  -- Dư Âm
  v_echo_pct numeric := coalesce((p_mods->>'echo_pct')::numeric, 0.6);
  v_pierce numeric := least(1, coalesce((p_mods->>'pierce')::numeric, 0)); -- Xuyên Giáp
  v_crit_pierce boolean := coalesce((p_mods->>'crit_pierce')::numeric, 0) > 0; -- Mắt Tử Thần
  v_revive numeric := coalesce((p_mods->>'revive')::numeric, 0);          -- Giả Chết (caller bỏ key khi đã dùng)
  v_revived boolean := false;
  v_atk_now numeric; v_def_now numeric; v_stack numeric;
  v_parried boolean; v_counter int; v_echo_dmg int;
  -- Bộ kỹ năng có hồi chiêu (get_skill_kit). Không có 'kit' → luân phiên a1/a2 như cũ.
  v_kit jsonb := p_mods->'kit';
  v_n int := coalesce(jsonb_array_length(p_mods->'kit'->'actives'), 0);
  v_cds int[] := array_fill(0, array[greatest(1, coalesce(jsonb_array_length(p_mods->'kit'->'actives'), 0))]);
  v_i int; v_best int; v_best_score numeric; v_score numeric; v_sk jsonb;
  v_eff jsonb := '{}'::jsonb;
  v_bonus numeric; v_multi int; v_hit_pierce numeric; v_stun_now boolean;
  v_dot_dmg int := 0; v_dot_left int := 0; v_dot_name text; v_tick int;
  v_stunned boolean := false;   -- quái bị đóng băng: mất lượt đánh kế
  v_chill boolean := false;     -- quái vừa mất lượt vì đóng băng (Băng Vỡ đánh mạnh hơn)
  v_stun_count int := 0;        -- đóng băng giảm dần: lần 2 tỉ lệ ×0.5, tối đa 2 lần/trận
  -- Dòng tiện ích trang bị (combat_mods)
  v_regen numeric := least(0.03, coalesce((p_mods->>'regen')::numeric, 0));
  v_skill_dmg numeric := least(0.5, coalesce((p_mods->>'skill_dmg')::numeric, 0));
  v_gear_red numeric := least(0.25, coalesce((p_mods->>'gear_dmg_red')::numeric, 0));
begin
  -- Bị động "Sát Thương Chí Mạng" cộng thẳng vào hệ số chí mạng
  v_crit_mult := v_crit_mult + coalesce((v_kit->>'crit_damage')::numeric, 0);

  while v_char_hp > 0 and v_enemy_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_kit is null then
      if v_turn % 2 = 1 then
        v_skill_name := p_a1_name; v_skill_power := p_a1_power;
      else
        v_skill_name := p_a2_name; v_skill_power := p_a2_power;
      end if;
    else
      -- Hồi chiêu: dùng skill sẵn sàng có sức mạnh hiệu dụng cao nhất, không có thì đánh thường
      for v_i in 1..v_n loop
        v_cds[v_i] := greatest(0, v_cds[v_i] - 1);
      end loop;
      v_best := 0; v_best_score := 1;
      for v_i in 1..v_n loop
        v_sk := v_kit->'actives'->(v_i - 1);
        continue when v_cds[v_i] > 0;
        continue when v_char_hp < p_max_hp * coalesce((v_sk->'effect'->>'min_hp')::numeric, 0);
        v_score := (v_sk->>'power')::numeric
          * (1 + case when v_turn >= 3 then coalesce((v_sk->'effect'->>'streak')::numeric, 0) else 0 end
               + case when v_chill then coalesce((v_sk->'effect'->>'bonus_stunned')::numeric, 0) else 0 end
               + case when v_enemy_hp < p_enemy_hp * 0.3 then coalesce((v_sk->'effect'->>'execute')::numeric, 0) else 0 end)
          * coalesce((v_sk->'effect'->>'hits')::numeric, 1);
        if v_score > v_best_score then v_best := v_i; v_best_score := v_score; end if;
      end loop;

      if v_best > 0 then
        v_sk := v_kit->'actives'->(v_best - 1);
        v_eff := coalesce(v_sk->'effect', '{}'::jsonb);
        v_skill_name := v_sk->>'name';
        v_skill_power := v_best_score / coalesce((v_eff->>'hits')::numeric, 1) * (1 + v_skill_dmg);
        v_cds[v_best] := coalesce((v_sk->>'cooldown')::int, 0);
      else
        v_eff := '{}'::jsonb;
        v_skill_name := 'Đánh thường'; v_skill_power := 1;
      end if;
      v_chill := false;

      -- Chém Tuyệt Vọng: tự mất % HP hiện tại
      if coalesce((v_eff->>'hp_cost')::numeric, 0) > 0 then
        v_char_hp := greatest(1, v_char_hp - greatest(1, round(v_char_hp * (v_eff->>'hp_cost')::numeric))::int);
      end if;
    end if;

    -- Phong Hầu: +x% ATK/DEF mỗi lượt đã qua (tối đa 10); Cuồng Huyết: ATK tăng dần khi HP
    -- tụt từ 100% xuống 40%
    -- Hồi HP mỗi lượt (dòng tiện ích trang bị)
    if v_regen > 0 and v_turn > 1 then
      v_char_hp := least(p_max_hp, v_char_hp + greatest(1, round(p_max_hp * v_regen))::int);
    end if;

    v_stack := least(10, v_turn - 1) * v_prestige;
    v_atk_now := p_char_atk * (1 + v_stack
      + v_rage * least(1, greatest(0, (1 - v_char_hp::numeric / greatest(1, p_max_hp)) / 0.6)));
    v_def_now := p_char_def * (1 + v_stack);

    -- Đòn Kép: đánh thêm 1 đòn trong lượt
    v_multi := coalesce((v_eff->>'hits')::int, 1);
    v_hits := v_multi + case when random() < v_double_chance then 1 else 0 end;
    v_hit_pierce := 1 - (1 - v_pierce) * (1 - least(1, coalesce((v_eff->>'pierce')::numeric, 0)));

    for v_hit in 1..v_hits loop
      exit when v_enemy_hp <= 0;

      v_is_crit := random() < p_crit;
      v_base_dmg := greatest(1, (v_atk_now * v_skill_power
        - case when v_is_crit and v_crit_pierce then 0 else p_enemy_def * (1 - v_hit_pierce) end) * v_gap_mult);
      v_opening := v_opening_mult > 1 and v_turn = 1 and v_hit = 1;
      if v_opening then
        v_base_dmg := v_base_dmg * v_opening_mult;   -- Khai Cuộc
      end if;
      v_dmg := round(v_base_dmg * (case when v_is_crit then v_crit_mult else 1 end));
      v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

      if p_lifesteal + coalesce((v_eff->>'lifesteal')::numeric, 0) > 0 then
        -- Khát Máu Vô Tận: HP dưới 30% thì hút máu nhân thêm
        v_char_hp := least(p_max_hp, v_char_hp + round(v_dmg * (p_lifesteal + coalesce((v_eff->>'lifesteal')::numeric, 0))
          * case when v_char_hp < p_max_hp * 0.3 then v_low_hp_ls else 1 end));
      end if;

      -- Hiệu ứng chỉ áp ở đòn đầu của skill: đóng băng, độc/thiêu
      v_stun_now := v_hit = 1 and coalesce((v_eff->>'stun')::numeric, 0) > 0 and v_stun_count < 2
                    and random() < (v_eff->>'stun')::numeric * power(0.5, v_stun_count);
      if v_stun_now then v_stunned := true; v_stun_count := v_stun_count + 1; end if;
      if v_hit = 1 and coalesce((v_eff->>'dot')::numeric, 0) > 0 then
        v_dot_dmg := greatest(1, round(v_atk_now * (v_eff->>'dot')::numeric))::int;
        v_dot_left := coalesce((v_eff->>'dot_turns')::int, 2);
        v_dot_name := coalesce(v_eff->>'dot_name', 'Độc');
      end if;

      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
          'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp,
          'double', v_hit > v_multi, 'opening', v_opening, 'stun', v_stun_now
        );
      end if;
    end loop;

    -- Dư Âm: cơ hội đánh thêm 1 đòn yếu cuối lượt
    if v_echo > 0 and v_enemy_hp > 0 and random() < v_echo then
      v_echo_dmg := round(greatest(1, (v_atk_now * v_echo_pct - p_enemy_def * (1 - v_pierce)) * v_gap_mult));
      v_enemy_hp := greatest(0, v_enemy_hp - v_echo_dmg);
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', 'Dư Âm',
          'damage', v_echo_dmg, 'crit', false, 'enemy_hp_left', v_enemy_hp, 'echo', true
        );
      end if;
    end if;

    -- Độc / thiêu: trừ máu quái cuối mỗi lượt của mình
    if v_dot_left > 0 and v_enemy_hp > 0 then
      v_tick := v_dot_dmg;
      v_enemy_hp := greatest(0, v_enemy_hp - v_tick);
      v_dot_left := v_dot_left - 1;
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_dot_name,
          'damage', v_tick, 'crit', false, 'enemy_hp_left', v_enemy_hp, 'dot', true
        );
      end if;
    end if;

    exit when v_enemy_hp <= 0;

    -- Đóng băng: quái mất lượt này
    if v_stunned then
      v_stunned := false;
      v_chill := true;
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
          'damage', 0, 'character_hp_left', v_char_hp, 'stunned', true, 'enemy_hp_left', v_enemy_hp
        );
      end if;
      continue;
    end if;

    -- Phản Kích: đỡ trọn đòn quái và đánh trả
    v_parried := v_parry > 0 and random() < v_parry;
    if v_parried then
      v_counter := round(greatest(1, (v_atk_now * v_parry_mult - p_enemy_def) * v_gap_mult));
      v_enemy_hp := greatest(0, v_enemy_hp - v_counter);
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
          'damage', 0, 'character_hp_left', v_char_hp, 'parry', v_counter, 'enemy_hp_left', v_enemy_hp
        );
      end if;
      continue;
    end if;

    -- DEF trừ thẳng nhưng quái luôn gây ít nhất 15% ATK của nó — trước đây sàn là 1,
    -- DEF nhân vật (cấp + VIT + đồ) vượt ATK quái nên quái gần như không gây sát thương
    -- Trụ Cột: mỗi lần trúng đòn trước đó +x% giảm sát thương (tối đa 3), chung trần 60%
    v_enemy_dmg := greatest(1, p_enemy_atk - v_def_now, p_enemy_atk * 0.15)
                   * p_damage_multiplier
                   * (1 - least(0.6, p_dmg_reduction + v_gear_red + least(3, v_guard_hits) * v_guard_step)) * v_guardian;
    v_enemy_hit := round(v_enemy_dmg);
    v_char_hp := greatest(0, v_char_hp - v_enemy_hit);
    v_dmg_taken := v_dmg_taken + v_enemy_hit;
    v_guard_hits := v_guard_hits + 1;

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

    -- Giả Chết: đòn chí tử đầu tiên để lại x% HP
    if v_char_hp <= 0 and v_revive > 0 and not v_revived then
      v_revived := true;
      v_char_hp := greatest(1, round(p_max_hp * v_revive));
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'system', 'revive', true,
          'message', 'Giả Chết! Gượng dậy với ' || v_char_hp || ' HP'
        );
      end if;
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

  return query select v_win, v_timed_out, v_char_hp, v_dmg_taken, v_log, v_revived;
end;
$$;

-- 4. Khám phá / Tháp / Nộm dùng combat_mods ---------------------------------------------
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
  v_mods := combat_mods(p_character_id);

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
  v_mods jsonb; v_revived boolean;
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
  v_mods := combat_mods(p_character_id);

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

create or replace function public.training_dummy(p_character_id uuid, p_armored boolean)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int;
  v_atk int; v_crit numeric; v_lifesteal numeric;
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_skill_lifesteal numeric; v_skill_crit numeric;
  v_effects text[];
  v_def int;
  v_log jsonb;
  v_hits jsonb;
begin
  select c.level into v_level from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select gs.atk, gs.crit_bonus, gs.lifesteal_bonus into v_atk, v_crit, v_lifesteal
  from get_character_stats(p_character_id) gs;

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_skill_lifesteal, v_skill_crit
  from get_combat_skills(p_character_id) cs;

  v_effects := get_character_effects(p_character_id);
  v_def := case when p_armored then round(0.8 * v_level * 1.3)::int else 0 end;

  select f.out_log into v_log
  from simulate_fight(
    v_atk, 0, 1000000000, 1000000000,
    least(0.75, v_crit + v_skill_crit), 0, 0,
    v_a1_name, v_a1_power, v_a2_name, v_a2_power,
    'Nộm Tập', 2000000000, 0, v_def,
    1, true, v_effects, combat_mods(p_character_id)
  ) f;

  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_hits
  from jsonb_array_elements(v_log) e where e->>'actor' = 'character';

  return jsonb_build_object(
    'turns', 30,
    'dummy_def', v_def,
    'total', (select coalesce(sum((e->>'damage')::int), 0) from jsonb_array_elements(v_hits) e),
    'hits', jsonb_array_length(v_hits),
    'max_hit', (select coalesce(max((e->>'damage')::int), 0) from jsonb_array_elements(v_hits) e),
    'crits', (select count(*) from jsonb_array_elements(v_hits) e where (e->>'crit')::boolean),
    'doubles', (select count(*) from jsonb_array_elements(v_hits) e where (e->>'double')::boolean),
    'atk', v_atk,
    'crit_chance', least(0.75, v_crit + v_skill_crit),
    'effects', to_jsonb(v_effects),
    'log', v_hits
  );
end;
$$;
