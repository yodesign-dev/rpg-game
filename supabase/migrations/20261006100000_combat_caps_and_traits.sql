-- Cân bằng cấp cao + đặc tính quái.
-- A. Công thức (simulate_fight):
--    - Chí mạng tối đa 50% (trước 75%); mỗi class có chí mạng khởi điểm riêng (classes.base_crit:
--      Chiến Binh 5%, Pháp Sư 8%, Xạ Thủ 10%, Sát Thủ 15%); AGI/DEX cộng chí mạng giảm dần (~30% trần).
--    - Hút máu từ chỉ số + bị động tối đa 10%, chỉ tính sát thương thật (không tính phần tràn).
--    - Sát thương quái: DEF giảm theo tỉ lệ DEF/(DEF + 20 + 6×cấp quái) thay vì trừ thẳng; hoà dần
--      Lv30→60 để giữ nguyên cân bằng cấp thấp.
-- B. Quái vùng / Tháp từ Lv30: HP × (1 + 1.2x), ATK × (1 + 1.8x), x = (cấp − 30) / 55
--    → Lv85: HP ×2.2, ATK ×2.8 (ATK tăng mạnh hơn để hút máu không hồi bù hết).
-- C. Đặc tính quái: mỗi vùng (từ Hang Động) 1 đặc tính; Tinh Anh +1, Hung Thần +2 ngẫu nhiên,
--    boss luôn Cuồng Nộ; Tháp từ tầng 11 đổi đặc tính mỗi 5 tầng.
-- Chạy thử trên Postgres local với bản sao Sát Thủ Lv85 thật (đồ, thiên phú, kỹ năng), đặt về Lv80
-- đánh Thiên Đường: trước 100/100 trận, 3 máu/trận, 1.3 lượt; sau 53–100/100, 250–380 máu/trận, 2.5 lượt.

-- 1. Dữ liệu -------------------------------------------------------------------------------
alter table classes add column if not exists base_crit numeric not null default 0.05;
update classes c set base_crit = v.crit
from (values ('warrior', 0.05), ('mage', 0.08), ('archer', 0.10), ('assassin', 0.15)) as v(key, crit)
where c.key = v.key;

alter table zones add column if not exists traits text[] not null default '{}';
update zones z set traits = v.traits
from (values
  ('hang_dong', array['evasive']), ('nui_tuyet', array['armored']), ('sa_mac', array['venom']),
  ('nui_lua', array['enrage']), ('vuc_toi', array['unholy']), ('thanh_dia', array['regen']),
  ('hu_khong', array['evasive']), ('hon_nguyen', array['thorny']), ('thien_duong', array['savage'])
) as v(key, traits)
where z.key = v.key;

create or replace function public.enemy_level_mult(p_level int, p_atk boolean default false)
returns numeric
language sql
immutable
as $$
  select 1 + case when p_atk then 1.8 else 1.2 end * greatest(0, least(p_level, 85) - 30) / 55.0;
$$;

-- Quái vùng từ Lv30 (chạy 1 lần — nhân trên chỉ số đang có)
update zone_enemies set hp = round(hp * enemy_level_mult(level)), atk = round(atk * enemy_level_mult(level, true))
where level > 30;

create or replace function public.enemy_extra_traits(p_n int, p_exclude text[])
returns text[]
language sql
volatile
as $$
  select coalesce(array_agg(t), '{}') from (
    select t from unnest(array['armored','evasive','savage','enrage','venom','regen','thorny','unholy']) t
    where not t = any(p_exclude)
    order by random() limit p_n
  ) x;
$$;

-- 2. Hàm -----------------------------------------------------------------------------------
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
    -- AGI 0.5 / DEX 0.3 "điểm chí mạng", giảm dần: 0.3 × r / (r + 0.5), tối đa ~30%
    -- (trước cộng thẳng, Sát Thủ dồn AGI lên >100% chí mạng)
    0.3 * (p_agi * 0.005 + p_dex * 0.003) / (p_agi * 0.005 + p_dex * 0.003 + 0.5);
$$;

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
    b.attr_crit + b.talent_crit + e.crit, b.talent_lifesteal + e.lifesteal
  from (
    -- Thiên phú: % nhân vào chỉ số gốc (không nhân trang bị), chí mạng/hút máu cộng thẳng
    select
      round((cl.base_hp + (ch.level - 1) * cl.hp_per_level + ab.attr_hp)
            * greatest(0.1, 1 + coalesce((t.j->>'hp_pct')::numeric, 0)))::int as base_max_hp,
      round((cl.base_atk + (ch.level - 1) * cl.atk_per_level + ab.attr_atk)
            * greatest(0.1, 1 + coalesce((t.j->>'atk_pct')::numeric, 0)))::int as base_atk,
      round((cl.base_def + (ch.level - 1) * cl.def_per_level + ab.attr_def)
            * greatest(0.1, 1 + coalesce((t.j->>'def_pct')::numeric, 0)))::int as base_def,
      cl.base_spd + (ch.level - 1) * cl.spd_per_level as base_spd,
      ab.attr_crit + cl.base_crit as attr_crit,   -- chí mạng khởi điểm theo class + AGI/DEX
      coalesce((t.j->>'crit')::numeric, 0) as talent_crit,
      coalesce((t.j->>'lifesteal')::numeric, 0) as talent_lifesteal
    from characters ch
    join classes cl on cl.id = ch.class_id
    cross join lateral attribute_bonuses(
      cl.main_stat, ch.stat_str, ch.stat_int, ch.stat_agi, ch.stat_dex, ch.stat_vit
    ) ab
    cross join lateral (select get_talent_totals(ch.id) as j) t
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

-- Thêm tham số → bỏ bản cũ để không thành 2 hàm cùng tên
drop function if exists public.simulate_fight(int, int, int, int, numeric, numeric, numeric, text, numeric, text, numeric, text, int, int, int, numeric, boolean, text[], jsonb, int);
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
      v_regen_e := least(p_enemy_hp - v_enemy_hp, round(p_enemy_hp * 0.04)::int);
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

-- Thêm cột out_traits → phải drop (đổi kiểu trả về)
drop function if exists public.tower_floor_enemies(int);
create or replace function public.tower_floor_enemies(p_floor int)
returns table(out_idx int, out_name text, out_level int, out_kind text,
              out_hp int, out_atk int, out_def int, out_exp int, out_gold int, out_traits text[])
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v_lvl int := greatest(1, least(100, p_floor));
  -- Khó hơn: HP ×(2 + 0.025 × tầng), ATK ×1.15, mỗi tầng +1% (trước 0.4%)
  -- Mỗi tầng +1%, từ tầng 30 quái mạnh thêm (khớp enemy_level_mult)
  v_tm numeric := 1 + v_lvl * 0.01;
  -- Đặc tính cố định theo tầng (xem trước = lúc đánh): từ tầng 11, đổi mỗi 5 tầng
  v_pool text[] := array['evasive','armored','venom','enrage','unholy','regen','thorny','savage'];
  v_base int := (p_floor / 5) % 8;
  v_trait text[] := case when v_lvl > 10 then array[v_pool[1 + v_base]] else '{}'::text[] end;
  v_hp numeric := (16 + 6 * v_lvl) * (2 + 0.025 * v_lvl) * enemy_level_mult(v_lvl);
  -- Tháp đã có +1%/tầng nên ATK chỉ theo đường cong HP (nhẹ hơn quái vùng)
  v_atk numeric := (case when v_lvl < 15 then 3 + 1.5 * v_lvl else 8 + 1.2 * v_lvl end) * 1.15
                   * enemy_level_mult(v_lvl);
  v_def numeric := 0.8 * v_lvl;
  v_name text;
  v_idx int := 0;
  k int;
begin
  if v_lvl % 10 = 0 then
    -- Tầng boss: các boss explore gần level nhất, mạnh dần về cuối
    for v_name in
      select b.name from (
        select ze.name, ze.level from zone_enemies ze where ze.is_boss
        order by abs(ze.level - v_lvl), ze.level desc
        limit ceil(v_lvl / 20.0)::int
      ) b order by b.level
    loop
      v_idx := v_idx + 1;
      return query select v_idx, v_name, v_lvl, 'boss',
        round(v_hp * 3 * v_tm)::int, round(v_atk * 1.25 * v_tm)::int, round(v_def * 1.2)::int,
        (1 + v_lvl) * 6, (1 + v_lvl) * 6,
        v_trait || array[v_pool[1 + (v_base + 1) % 8], v_pool[1 + (v_base + 3 + v_idx) % 8]];
    end loop;
    return;
  end if;

  if v_lvl % 5 = 0 then
    select ze.name into v_name from zone_enemies ze where not ze.is_boss
    order by abs(ze.level - v_lvl), ze.level desc limit 1;
    v_idx := 1;
    return query select 1, 'Tinh Anh ' || v_name, v_lvl + 1, 'elite',
      round(v_hp * 2 * v_tm)::int, round(v_atk * 1.15 * v_tm)::int, round(v_def * 1.15)::int,
      (2 + v_lvl) * 3, (2 + v_lvl) * 3,
      v_trait || array[v_pool[1 + (v_base + 2) % 8]];
  end if;

  for k in (v_idx + 1)..2 loop
    select ze.name into v_name from zone_enemies ze where not ze.is_boss
    order by abs(ze.level - v_lvl), ze.name limit 1 offset ((v_lvl + k) % 3);
    return query select k, v_name, v_lvl, 'normal',
      round(v_hp * v_tm)::int, round(v_atk * v_tm)::int, round(v_def)::int,
      1 + v_lvl, 1 + v_lvl, v_trait;
  end loop;
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
    v_traits := v_zone.traits || case
      when v_is_boss then array['enrage']
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
      'traits', to_jsonb(v_traits),
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
  v_crit_chance := least(0.5, v_crit_chance + v_stat_crit_bonus);
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
          v_enemy.out_level - v_level, v_enemy.out_traits, v_enemy.out_level
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
        'hp_left', v_hp, 'dmg_taken', v_dmg_taken, 'log', v_fight_log,
        'traits', to_jsonb(v_enemy.out_traits)
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
    least(0.5, v_crit + v_skill_crit), 0, 0,
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
    'crit_chance', least(0.5, v_crit + v_skill_crit),
    'effects', to_jsonb(v_effects),
    'log', v_hits
  );
end;
$$;
