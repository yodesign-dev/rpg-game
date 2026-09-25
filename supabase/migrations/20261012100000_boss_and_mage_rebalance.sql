-- Cân bằng boss + Pháp Sư.
-- A. Boss Thám Hiểm: HP boss ×4 → ×2.5 và ATK ×1.4 → ×1.25 so với quái thường (hệ số hardcore và
--    hệ số theo cấp giữ nguyên). Trước đây ba hệ số nhân chồng → Đấng Sáng Thế trâu ~34 lần quái thường,
--    từ Thẩm Phán Thánh Quang (Lv56) trở lên gần như không ai thắng.
--    Tái Sinh trên boss 4% → 1.5% HP mỗi lượt (explore gắn dấu 'boss' vào đặc tính).
--    Gục trước boss gặp ngẫu nhiên: không mất vàng / EXP. Núi Lửa hết bị gắn Cuồng Nộ 2 lần.
--    Tháp không đổi.
-- B. Pháp Sư: HP gốc 95 → 110; Khiên Mana 12% → 15%; Băng Tiễn đóng băng 20% → 35%;
--    Băng Vỡ thưởng khi quái bị đóng băng +40% → +60%; Thiên Thạch 130% → 170%, thiêu 10% → 15% × 3 lượt.

-- 1. Dữ liệu ---------------------------------------------------------------------------------
-- Boss (chạy 1 lần — nhân trên chỉ số đang có)
update zone_enemies set hp = round(hp * 2.5 / 4), atk = round(atk * 1.25 / 1.4) where is_boss;

update classes set base_hp = 110 where key = 'mage';
update skills set effect_value = 0.15, description = 'Giảm 15% sát thương nhận vào' where key = 'mage_shield';
update skills set effect = '{"pierce": 1, "stun": 0.35}'::jsonb,
  description = '140% ATK phép xuyên giáp, 35% đóng băng quái 1 lượt' where key = 'mage_frost';
update skills set effect = '{"pierce": 1, "bonus_stunned": 0.6}'::jsonb,
  description = '200% ATK phép xuyên giáp; +60% nếu quái vừa bị đóng băng' where key = 'mage_shatter';
update skills set power_multiplier = 1.7,
  effect = '{"pierce": 1, "dot": 0.15, "dot_turns": 3, "dot_name": "Thiêu đốt"}'::jsonb,
  description = '170% ATK phép xuyên giáp + thiêu 15% ATK mỗi lượt trong 3 lượt' where key = 'mage_meteor';

-- 2. Hàm -------------------------------------------------------------------------------------
create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean,
  p_effects text[] default '{}',
  p_mods jsonb default '{}',      -- tổng thiên phú (get_talent_totals) + 'kit' (get_skill_kit)
  p_level_gap int default 0,      -- cấp quái − cấp nhân vật (> 0: đánh vượt cấp)
  p_enemy_traits text[] default '{}', -- đặc tính quái (mô tả: ENEMY_TRAITS, lib/enemies.ts)
  p_enemy_level int default 0     -- cấp quái: hằng số DEF theo tỉ lệ
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
  -- Đặc tính quái
  v_t_armored boolean := 'armored' = any(p_enemy_traits);  -- Giáp Cứng: chí mạng yếu, không xuyên giáp
  v_t_evasive boolean := 'evasive' = any(p_enemy_traits);  -- Né Tránh: 15% đòn trượt
  v_t_savage boolean := 'savage' = any(p_enemy_traits);    -- Hung Bạo: quái chí mạng 15% ×1.5
  v_t_enrage boolean := 'enrage' = any(p_enemy_traits);    -- Cuồng Nộ: dưới 50% HP ATK ×1.3
  v_t_venom boolean := 'venom' = any(p_enemy_traits);      -- Độc: trúng đòn bị độc 2% HP/lượt
  v_t_regen boolean := 'regen' = any(p_enemy_traits);      -- Tái Sinh: hồi 4% HP mỗi lượt
  v_t_thorny boolean := 'thorny' = any(p_enemy_traits);    -- Gai: phản 4% sát thương nhận
  v_ls_mult numeric := case when 'unholy' = any(p_enemy_traits) then 0.5 else 1 end; -- Ô Uế: hút máu −50%
  v_miss boolean; v_real int; v_reflect int; v_poison int := 0; v_poison_tick int; v_regen_e int;
  v_enemy_crit boolean; v_enraged boolean; v_enrage_logged boolean := false;
  -- Sát thương quái: DEF giảm theo tỉ lệ DEF/(DEF+K) thay vì trừ thẳng (DEF cao không vô hiệu
  -- hoá quái). Hoà dần từ Lv30 (công thức cũ) tới Lv60 (công thức mới) để giữ cân bằng cấp thấp.
  v_k numeric := 20 + 6 * greatest(1, p_enemy_level);
  v_blend numeric := least(1, greatest(0, (p_enemy_level - 30) / 30.0));
  v_old_dmg numeric; v_ratio_dmg numeric;
begin
  -- Trần chung: chí mạng 50%, hút máu (chỉ số + bị động) 10%
  p_crit := least(0.5, p_crit);
  p_lifesteal := least(0.10, p_lifesteal);
  -- Bị động "Sát Thương Chí Mạng" cộng thẳng vào hệ số chí mạng
  v_crit_mult := v_crit_mult + coalesce((v_kit->>'crit_damage')::numeric, 0);
  if v_t_armored then
    v_crit_mult := 1 + (v_crit_mult - 1) * 0.5;
    v_crit_pierce := false;
  end if;

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

      v_miss := v_t_evasive and random() < 0.15;
      if v_miss then
        if p_with_log then
          v_log := v_log || jsonb_build_object(
            'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
            'damage', 0, 'miss', true, 'enemy_hp_left', v_enemy_hp
          );
        end if;
        continue;
      end if;

      v_is_crit := random() < p_crit;
      v_base_dmg := greatest(1, (v_atk_now * v_skill_power
        - case when v_is_crit and v_crit_pierce then 0 else p_enemy_def * (1 - v_hit_pierce) end) * v_gap_mult);
      v_opening := v_opening_mult > 1 and v_turn = 1 and v_hit = 1;
      if v_opening then
        v_base_dmg := v_base_dmg * v_opening_mult;   -- Khai Cuộc
      end if;
      v_dmg := round(v_base_dmg * (case when v_is_crit then v_crit_mult else 1 end));
      -- Hút máu / phản gai chỉ tính phần sát thương thật (không tính phần tràn khi quái đã hết máu)
      v_real := least(v_dmg, v_enemy_hp);
      v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

      if p_lifesteal + coalesce((v_eff->>'lifesteal')::numeric, 0) > 0 then
        -- Khát Máu Vô Tận: HP dưới 30% thì hút máu nhân thêm
        v_char_hp := least(p_max_hp, v_char_hp + round(v_real * (p_lifesteal + coalesce((v_eff->>'lifesteal')::numeric, 0))
          * v_ls_mult * case when v_char_hp < p_max_hp * 0.3 then v_low_hp_ls else 1 end));
      end if;

      v_reflect := case when v_t_thorny then round(v_real * 0.04)::int else 0 end;
      if v_reflect > 0 then
        v_char_hp := greatest(1, v_char_hp - v_reflect);
        v_dmg_taken := v_dmg_taken + v_reflect;
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
          'double', v_hit > v_multi, 'opening', v_opening, 'stun', v_stun_now, 'reflect', v_reflect
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

    -- Tái Sinh: quái hồi máu đầu lượt của nó
    v_regen_e := 0;
    if v_t_regen then
      -- Boss (dấu 'boss' trong đặc tính) chỉ hồi 1.5%: 4% trên cả nghìn HP ăn hết sát thương mỗi lượt
      v_regen_e := least(p_enemy_hp - v_enemy_hp,
        round(p_enemy_hp * case when 'boss' = any(p_enemy_traits) then 0.015 else 0.04 end)::int);
      v_enemy_hp := v_enemy_hp + v_regen_e;
    end if;

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
    v_old_dmg := greatest(1, p_enemy_atk - v_def_now, p_enemy_atk * 0.15);
    v_ratio_dmg := p_enemy_atk * v_k / (v_k + greatest(0, v_def_now));
    v_enraged := v_t_enrage and v_enemy_hp < p_enemy_hp * 0.5;
    v_enemy_crit := v_t_savage and random() < 0.15;
    v_enemy_dmg := (v_old_dmg * (1 - v_blend) + greatest(v_old_dmg, v_ratio_dmg) * v_blend)
                   * case when v_enraged then 1.3 else 1 end
                   * case when v_enemy_crit then 1.5 else 1 end
                   * p_damage_multiplier
                   * (1 - least(0.6, p_dmg_reduction + v_gear_red + least(3, v_guard_hits) * v_guard_step)) * v_guardian;
    v_enemy_hit := round(v_enemy_dmg);
    v_char_hp := greatest(0, v_char_hp - v_enemy_hit);
    v_dmg_taken := v_dmg_taken + v_enemy_hit;
    v_guard_hits := v_guard_hits + 1;

    -- Độc: ngấm từ đòn trước, trúng đòn thì (lại) bị độc
    v_poison_tick := 0;
    if v_poison > 0 and v_char_hp > 0 then
      v_poison_tick := v_poison;
      v_char_hp := greatest(0, v_char_hp - v_poison_tick);
      v_dmg_taken := v_dmg_taken + v_poison_tick;
    end if;
    if v_t_venom then v_poison := greatest(1, round(p_max_hp * 0.02)::int); end if;

    -- Phản Đòn: 20% sát thương nhận vào dội lại quái
    v_thorns := case when v_thorns_on then round(v_enemy_hit * 0.2) else 0 end;
    if v_thorns > 0 then
      v_enemy_hp := greatest(0, v_enemy_hp - v_thorns);
    end if;

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
        'damage', v_enemy_hit, 'character_hp_left', v_char_hp,
        'thorns', v_thorns, 'enemy_hp_left', v_enemy_hp,
        'enemy_crit', v_enemy_crit, 'enraged', v_enraged and not v_enrage_logged,
        'poison', v_poison_tick, 'regen', v_regen_e
      );
      v_enrage_logged := v_enrage_logged or v_enraged;
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
  v_tier text; v_tier_roll numeric; v_name text; v_traits text[];
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
  v_died_to_boss boolean := false;
  -- Pet: nội tại % EXP/vàng/rơi đồ của pet đang mang + gặp pet hoang dã sau trận thắng
  v_pet jsonb; v_pet_exp numeric; v_pet_gold numeric; v_pet_drop numeric;
  v_pending_pets int; v_pet_chance numeric; v_pet_roll numeric; v_pet_rarity text; v_fight_pet text;
  v_pets_found jsonb := '[]'::jsonb;
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

  v_crit_chance := least(0.5, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;
  v_effects := get_character_effects(p_character_id);
  v_mods := combat_mods(p_character_id);
  v_pet := pet_mods(p_character_id);
  v_pet_exp := 1 + coalesce((v_pet->>'exp_pct')::numeric, 0);
  v_pet_gold := 1 + coalesce((v_pet->>'gold_pct')::numeric, 0);
  v_pet_drop := 1 + coalesce((v_pet->>'drop_pct')::numeric, 0);
  delete from pet_encounters pe where pe.character_id = p_character_id and pe.expires_at < now();
  select count(*) into v_pending_pets from pet_encounters pe where pe.character_id = p_character_id;

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
    -- Đặc tính: của vùng + Tinh Anh thêm 1, Hung Thần thêm 2 (ngẫu nhiên), boss luôn Cuồng Nộ
    -- (không lặp nếu vùng đã có) + dấu 'boss' (web bỏ qua; simulate_fight giảm Tái Sinh)
    v_traits := v_zone.traits || case
      when v_is_boss then array['boss'] || case when 'enrage' = any(v_zone.traits) then '{}'::text[] else array['enrage'] end
      when v_tier = 'elite' then enemy_extra_traits(1, v_zone.traits)
      when v_tier = 'champion' then enemy_extra_traits(2, v_zone.traits)
      else '{}'::text[] end;

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
      v_enemy.level - v_level, v_traits, v_enemy.level
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
    -- Giả Chết chỉ 1 lần mỗi chuyến
    if v_revived then v_mods := v_mods - 'revive'; end if;

    v_last_fight := jsonb_build_object(
      'turn', v_turn, 'enemy', v_name, 'level', v_enemy.level, 'boss', v_is_boss, 'log', v_fight_log
    );

    v_fight_exp := 0; v_fight_gold := 0;
    v_fight_drops := '[]'::jsonb;
    v_fight_pet := null;

    if v_win then
      v_wins := v_wins + 1;
      if v_is_boss then v_boss_wins := v_boss_wins + 1; end if;

      if v_is_boss then
        perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
          'boss', v_enemy.name, 'where', v_zone.icon || ' ' || v_zone.name, 'source', 'explore'
        ));
      end if;
      v_fight_exp := round(v_enemy.reward_exp * v_reward_mult * v_exp_multiplier * case when v_buff_exp then 1.25 else 1 end * v_pet_exp);
      v_fight_gold := round(v_enemy.reward_gold * v_reward_mult * v_exp_multiplier * v_pet_gold);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate * v_drop_mult * case when v_buff_luck then 1.3 else 1 end * v_pet_drop;
        -- Hung Thần tung độ hiếm trang bị như boss
        v_drop_rarity := grant_drop(p_character_id, v_drop.item_id, v_is_boss or v_tier = 'champion');
        v_fight_drops := v_fight_drops || jsonb_build_object('key', v_drop.key, 'rarity', v_drop_rarity);
        -- Gộp theo cặp item|tier (cùng 1 món có thể rơi ra nhiều tier khác nhau)
        v_drop_counts := jsonb_set(
          v_drop_counts, array[v_drop.key || '|' || v_drop_rarity],
          to_jsonb(coalesce((v_drop_counts ->> (v_drop.key || '|' || v_drop_rarity))::int, 0) + 1)
        );
      end loop;

      -- Pet hoang dã: 1,5% sau trận thắng quái thường (Tinh Anh 3%, Hung Thần 5%), không gặp ở boss.
      -- Độ hiếm 60/28/10/2%; Tinh Anh / Hung Thần nghiêng về hiếm hơn. Tối đa 10 pet chờ bắt.
      v_pet_chance := case v_tier when 'champion' then 0.05 when 'elite' then 0.03 else 0.015 end;
      if not v_is_boss and v_enemy.catchable and v_pending_pets < 10 and random() < v_pet_chance then
        v_pet_roll := random() * case v_tier when 'champion' then 0.5 when 'elite' then 0.75 else 1 end;
        v_pet_rarity := case when v_pet_roll < 0.02 then 'legendary' when v_pet_roll < 0.12 then 'epic'
                             when v_pet_roll < 0.40 then 'rare' else 'common' end;
        insert into pet_encounters (character_id, zone_id, species, level, rarity)
        values (p_character_id, p_zone_id, v_enemy.name, v_enemy.level, v_pet_rarity);
        v_pending_pets := v_pending_pets + 1;
        v_fight_pet := v_pet_rarity;
        v_pets_found := v_pets_found || jsonb_build_object(
          'species', v_enemy.name, 'rarity', v_pet_rarity, 'level', v_enemy.level);
      end if;
    end if;

    v_fights := v_fights || jsonb_build_object(
      'turn', v_turn,
      'enemy', v_name,
      'level', v_enemy.level,
      'boss', v_is_boss,
      'tier', v_tier,
      'traits', to_jsonb(v_traits),
      'log', v_fight_log,
      'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
      'hp_left', v_hp,
      'dmg_taken', v_dmg_taken,
      'exp', v_fight_exp,
      'gold', v_fight_gold,
      'drops', v_fight_drops,
      'pet', v_fight_pet
    );

    v_turns_completed := v_turn;

    -- Hết HP: dừng, thưởng chỉ tính các trận đã thắng trước đó
    if not v_win and not v_timed_out then
      if not v_buff_guard then
        v_died := true;
        v_died_to_boss := v_is_boss;
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

  -- Phạt khi gục: mất 10% vàng đang cầm và 15% EXP của cấp hiện tại (không tụt cấp).
  -- Gục trước boss gặp ngẫu nhiên thì không phạt.
  if v_died and not v_died_to_boss then
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
    'died_to_boss', v_died_to_boss,
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
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck),
    'pets', v_pets_found
  );
end;
$$;
