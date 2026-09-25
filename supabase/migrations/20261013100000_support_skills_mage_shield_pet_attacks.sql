-- Kỹ năng hỗ trợ + Pháp Sư bền hơn + pet đánh theo (tham khảo DautoRPG).
-- A. Skill hỗ trợ (skills.effect.buff, mở ở Lv18, chiếm 1 ô chủ động): dùng ngay khi hồi xong và
--    đủ điều kiện HP, không tốn lượt đánh.
--    Chiến Binh Hào Quang (giảm 35% sát thương 3 lượt, HP < 80%), Pháp Sư Khiên Băng (chặn trọn 2 đòn,
--    HP < 50%), Sát Thủ Ẩn Thân (né đòn kế tiếp + đòn lượt này chắc chắn chí mạng, HP < 70%),
--    Xạ Thủ Lướt Gió (40% né đòn trong 3 lượt, HP < 70%). Hồi chiêu tính trong từng trận.
-- B. Pháp Sư: Khiên Mana (Lv5) giảm 15% sát thương → quỹ lá chắn 15% HP tối đa mỗi trận, đỡ 50% mỗi đòn
--    tới khi cạn (lá chắn đỡ 100% làm mới mỗi trận thì Pháp Sư gần như bất tử ở Thám Hiểm);
--    Tập Trung (Lv35) → Dư Âm Phép: sau mỗi skill 30% bắn thêm 70% ATK phép xuyên giáp.
-- Chạy simulate_fight thật trên PGlite (chuỗi Thám Hiểm không bình, quái đúng cấp + 12% Tinh Anh):
--    Pháp Sư Lv45 sống 17 → 27 trận liên tiếp (55 nếu mang Khiên Băng), Lv60 4.4 → 7.3; class khác
--    tăng nhẹ khi mang skill hỗ trợ; pet Hộ Thân mạnh nhất (+50–100% số trận).
-- C. Pet đang mang đánh theo mỗi lượt: 8/12/18/25% ATK (thường/hiếm/sử thi/huyền thoại) và có
--    1 skill theo loài, hồi 4 lượt (sức mạnh ×1/1.25/1.5/2): Chữa Lành (hồi 3% HP tối đa), Hộ Thân
--    (chặn 1 đòn), Hơi Băng (10% đóng băng), Cắn Xé / Phun Độc / Phun Lửa (40% đòn pet mỗi lượt × 3).

-- 1. Dữ liệu ---------------------------------------------------------------------------------
comment on column skills.effect is
  'Skill chủ động: pierce, lifesteal, hp_cost, min_hp, stun, bonus_stunned, dot/dot_turns/dot_name, streak, execute, hits. '
  'Skill hỗ trợ: buff = block (block) | dr (pct, turns) | vanish | evade (pct, turns), use_below_hp';
comment on column skills.effect_type is 'Bị động: damage_reduction | lifesteal | crit_chance | crit_damage | barrier | spell_echo';

update skills set effect_type = 'barrier', effect_value = 0.15,
  description = 'Mỗi trận có lá chắn phép bằng 15% HP tối đa, đỡ 50% sát thương mỗi đòn tới khi cạn'
where key = 'mage_shield';
update skills set name = 'Dư Âm Phép', effect_type = 'spell_echo', effect_value = 0.3, icon = '🌀',
  description = 'Sau mỗi skill, 30% bắn thêm 70% ATK phép xuyên giáp'
where key = 'mage_focus';

insert into skills (class_id, key, name, description, skill_type, power_multiplier, cooldown, effect, unlock_level, icon)
select cl.id, v.key, v.name, v.description, 'active', null, v.cooldown, v.effect, 18, v.icon
from (values
  ('warrior', 'warrior_aura', 'Hào Quang', 'Hỗ trợ: giảm 35% sát thương nhận trong 3 lượt. Tự dùng khi HP dưới 80%, không tốn lượt đánh',
   6, '{"buff": "dr", "pct": 0.35, "turns": 3, "use_below_hp": 0.8}'::jsonb, '🌟'),
  ('mage', 'mage_ice_shield', 'Khiên Băng', 'Hỗ trợ: chặn trọn 2 đòn kế tiếp. Tự dùng khi HP dưới 50%, không tốn lượt đánh',
   6, '{"buff": "block", "block": 2, "use_below_hp": 0.5}'::jsonb, '💠'),
  ('assassin', 'assassin_vanish', 'Ẩn Thân', 'Hỗ trợ: né đòn kế tiếp của quái, đòn đánh lượt này chắc chắn chí mạng. Tự dùng khi HP dưới 70%',
   5, '{"buff": "vanish", "use_below_hp": 0.7}'::jsonb, '🌫️'),
  ('archer', 'archer_gale', 'Lướt Gió', 'Hỗ trợ: 40% né đòn của quái trong 3 lượt. Tự dùng khi HP dưới 70%, không tốn lượt đánh',
   6, '{"buff": "evade", "pct": 0.4, "turns": 3, "use_below_hp": 0.7}'::jsonb, '💨')
) as v(class_key, key, name, description, cooldown, effect, icon)
join classes cl on cl.key = v.class_key
on conflict (key) do nothing;

-- Skill của pet theo loài (khớp PET_SKILLS, lib/pets.ts)
create table if not exists pet_species_skills (
  species text primary key,
  skill   text not null check (skill in ('heal', 'guard', 'bleed', 'poison', 'freeze', 'burn'))
);
alter table pet_species_skills enable row level security;
drop policy if exists "pet_species_skills read" on pet_species_skills;
create policy "pet_species_skills read" on pet_species_skills for select using (true);
grant select on table pet_species_skills to anon, authenticated;

insert into pet_species_skills (species, skill) values
  ('Slime Xanh', 'heal'), ('Yêu Tinh Rừng', 'heal'), ('Bù Nhìn Ma', 'heal'), ('Mắt Hư Không', 'heal'),
  ('Sứa Không Gian', 'heal'), ('Tinh Thể Sống', 'heal'), ('Thiên Nhãn', 'heal'),
  ('Bọ Giáp Hang', 'guard'), ('Goblin Thợ Mỏ', 'guard'), ('Orc', 'guard'), ('Ancient Golem', 'guard'),
  ('Yeti', 'guard'), ('Xác Ướp', 'guard'), ('Golem Dung Nham', 'guard'), ('Tượng Thần Canh Gác', 'guard'),
  ('Người Khổng Lồ Pha Lê', 'guard'),
  ('Sói Rừng', 'bleed'), ('Lợn Rừng', 'bleed'), ('Ong Bắp Cày', 'bleed'), ('Vua Châu Chấu', 'bleed'),
  ('Sâu Cát Khổng Lồ', 'bleed'), ('Sư Tử Thần', 'bleed'), ('Kẻ Nuốt Sao', 'bleed'),
  ('Rắn Cỏ', 'poison'), ('Sâu Đồng', 'poison'), ('Nhện Hang', 'poison'), ('Bọ Cạp Cát', 'poison'),
  ('Rắn Hổ Mang', 'poison'), ('Nhện Bóng Tối', 'poison'), ('Nguyên Tố Hỗn Mang', 'poison'),
  ('Sói Tuyết', 'freeze'), ('Hồn Ma Băng', 'freeze'), ('Rồng Băng Non', 'freeze'),
  ('Thằn Lằn Lửa', 'burn'), ('Tinh Linh Lửa', 'burn'), ('Chó Địa Ngục', 'burn'), ('Rồng Lửa Cổ Đại', 'burn'),
  ('Rồng Nguyên Tố', 'burn')
on conflict (species) do update set skill = excluded.skill;

-- 2. Hàm -------------------------------------------------------------------------------------
create or replace function public.get_skill_kit(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = 'public'
as $$
  select jsonb_build_object(
    'actives', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', s.name, 'power', s.power_multiplier, 'cooldown', s.cooldown, 'effect', s.effect
             ) order by s.unlock_level)
      from character_equipped_skills ces join skills s on s.id = ces.skill_id
      where ces.character_id = p_character_id and s.skill_type = 'active'), '[]'::jsonb),
    'crit_damage', coalesce(sum(s.effect_value) filter (where s.effect_type = 'crit_damage'), 0),
    'barrier', coalesce(sum(s.effect_value) filter (where s.effect_type = 'barrier'), 0),
    'spell_echo', coalesce(sum(s.effect_value) filter (where s.effect_type = 'spell_echo'), 0)
  )
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'passive';
$$;

-- Pet đang mang cho vòng đánh: {name, rarity, pct, power, skill} hoặc null
create or replace function public.pet_combat(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = 'public'
as $$
  select jsonb_build_object(
    'name', cp.species, 'rarity', cp.rarity,
    'pct', case cp.rarity when 'legendary' then 0.25 when 'epic' then 0.18 when 'rare' then 0.12 else 0.08 end,
    'power', case cp.rarity when 'legendary' then 2 when 'epic' then 1.5 when 'rare' then 1.25 else 1 end,
    'skill', ps.skill
  )
  from character_pets cp left join pet_species_skills ps on ps.species = cp.species
  where cp.character_id = p_character_id and cp.active
  limit 1;
$$;

create or replace function public.combat_mods(p_character_id uuid)
returns jsonb
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v jsonb := get_bonus_totals(p_character_id);
  g jsonb := get_gear_mods(p_character_id);
  p jsonb;
  k text;
begin
  for k in select jsonb_object_keys(g) loop
    if k = 'dmg_red' then
      v := v || jsonb_build_object('gear_dmg_red', coalesce((v->>'gear_dmg_red')::numeric, 0) + (g->>k)::numeric);
    else
      v := v || jsonb_build_object(k, coalesce((v->>k)::numeric, 0) + (g->>k)::numeric);
    end if;
  end loop;
  -- Hộ Vệ của pet cộng chung trần giảm sát thương với trang bị (simulate_fight: tối đa 25%)
  if v ? 'pet_dmg_red' then
    v := v || jsonb_build_object('gear_dmg_red', coalesce((v->>'gear_dmg_red')::numeric, 0) + (v->>'pet_dmg_red')::numeric);
  end if;
  p := pet_combat(p_character_id);
  return v || jsonb_build_object('kit', get_skill_kit(p_character_id))
           || case when p is null then '{}'::jsonb else jsonb_build_object('pet', p) end;
end;
$$;


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
  -- Skill hỗ trợ (effect.buff) + bị động Khiên Mana (lá chắn) / Dư Âm Phép trong kit
  v_barrier int := 0; v_absorbed int := 0;
  v_spell_echo numeric := least(0.5, coalesce((p_mods->'kit'->>'spell_echo')::numeric, 0));
  v_used_skill boolean := false;
  v_block int := 0;                                  -- chặn trọn n đòn kế tiếp của quái
  v_vanish boolean := false; v_force_crit boolean := false;  -- Ẩn Thân
  v_drbuff numeric := 0; v_drbuff_left int := 0;     -- Hào Quang
  v_evade numeric := 0; v_evade_left int := 0;       -- Lướt Gió
  v_buff_msg text; v_buff text;
  -- Pet đánh theo (combat_mods → 'pet'): mỗi lượt 1 đòn % ATK, skill riêng hồi 4 lượt
  v_pet_pct numeric := coalesce((p_mods->'pet'->>'pct')::numeric, 0);
  v_pet_skill text := p_mods->'pet'->>'skill';
  v_pet_power numeric := coalesce((p_mods->'pet'->>'power')::numeric, 1);
  v_pet_name text := p_mods->'pet'->>'name';
  v_pet_cd int := 0;
  v_pet_dmg int; v_pet_heal int; v_pet_stun boolean; v_pet_used text;
  v_pdot_dmg int := 0; v_pdot_left int := 0; v_pdot_name text;
  v_old_dmg numeric; v_ratio_dmg numeric;
begin
  -- Trần chung: chí mạng 50%, hút máu (chỉ số + bị động) 10%
  p_crit := least(0.5, p_crit);
  p_lifesteal := least(0.10, p_lifesteal);
  -- Khiên Mana: quỹ lá chắn = x% HP tối đa, làm mới mỗi trận, đỡ 50% sát thương mỗi đòn tới khi cạn
  v_barrier := round(p_max_hp * least(0.6, coalesce((v_kit->>'barrier')::numeric, 0)))::int;
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
      v_drbuff_left := greatest(0, v_drbuff_left - 1);
      v_evade_left := greatest(0, v_evade_left - 1);

      -- Skill hỗ trợ: dùng ngay khi hồi xong (và HP dưới ngưỡng use_below_hp nếu có),
      -- không tốn lượt đánh — cái giá là chiếm 1 ô skill chủ động
      for v_i in 1..v_n loop
        v_sk := v_kit->'actives'->(v_i - 1);
        continue when not (v_sk->'effect' ? 'buff') or v_cds[v_i] > 0;
        continue when v_sk->'effect' ? 'use_below_hp'
                      and v_char_hp >= p_max_hp * (v_sk->'effect'->>'use_below_hp')::numeric;
        v_cds[v_i] := coalesce((v_sk->>'cooldown')::int, 0);
        v_buff := v_sk->'effect'->>'buff';
        if v_buff = 'block' then
          v_block := greatest(v_block, (v_sk->'effect'->>'block')::int);
          v_buff_msg := 'chặn trọn ' || v_block || ' đòn kế tiếp';
        elsif v_buff = 'dr' then
          v_drbuff := (v_sk->'effect'->>'pct')::numeric;
          v_drbuff_left := (v_sk->'effect'->>'turns')::int;
          v_buff_msg := 'giảm ' || round(v_drbuff * 100) || '% sát thương nhận trong ' || v_drbuff_left || ' lượt';
        elsif v_buff = 'vanish' then
          v_vanish := true; v_force_crit := true;
          v_buff_msg := 'né đòn kế tiếp, đòn này chắc chắn chí mạng';
        elsif v_buff = 'evade' then
          v_evade := (v_sk->'effect'->>'pct')::numeric;
          v_evade_left := (v_sk->'effect'->>'turns')::int;
          v_buff_msg := round(v_evade * 100) || '% né đòn trong ' || v_evade_left || ' lượt';
        end if;
        if p_with_log then
          v_log := v_log || jsonb_build_object(
            'turn', v_turn, 'actor', 'character', 'skill', v_sk->>'name', 'buff', true, 'message', v_buff_msg
          );
        end if;
      end loop;

      v_best := 0; v_best_score := 1;
      for v_i in 1..v_n loop
        v_sk := v_kit->'actives'->(v_i - 1);
        continue when v_cds[v_i] > 0 or v_sk->'effect' ? 'buff';
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
      v_used_skill := v_best > 0;

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

      -- Ẩn Thân: đòn kế chắc chắn chí mạng
      v_is_crit := v_force_crit or random() < p_crit;
      v_force_crit := false;
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

    -- Dư Âm Phép (bị động Pháp Sư): sau skill có x% bắn thêm 70% ATK phép xuyên giáp
    if v_used_skill and v_spell_echo > 0 and v_enemy_hp > 0 and random() < v_spell_echo then
      v_echo_dmg := round(greatest(1, v_atk_now * 0.7 * v_gap_mult));
      v_enemy_hp := greatest(0, v_enemy_hp - v_echo_dmg);
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', 'Dư Âm Phép',
          'damage', v_echo_dmg, 'crit', false, 'enemy_hp_left', v_enemy_hp, 'echo', true
        );
      end if;
    end if;

    -- Pet: skill riêng (hồi 4 lượt) rồi đánh 1 đòn theo % ATK. Không chí mạng, không hút máu.
    if v_pet_pct > 0 and v_enemy_hp > 0 then
      v_pet_cd := greatest(0, v_pet_cd - 1);
      v_pet_used := null; v_pet_heal := 0; v_pet_stun := false;
      if v_pet_cd = 0 and v_pet_skill is not null then
        v_pet_cd := 4;
        v_pet_used := v_pet_skill;
        if v_pet_skill = 'heal' and v_char_hp >= p_max_hp * 0.8 then
          v_pet_cd := 0; v_pet_used := null;   -- Chữa Lành: chờ tới khi HP dưới 80%
        elsif v_pet_skill = 'heal' then
          v_pet_heal := least(p_max_hp - v_char_hp, round(p_max_hp * 0.03 * v_pet_power))::int;
          v_char_hp := v_char_hp + v_pet_heal;
        elsif v_pet_skill = 'guard' then
          v_block := v_block + 1;
        elsif v_pet_skill = 'freeze' then
          v_pet_stun := v_stun_count < 2 and random() < 0.1 * v_pet_power;
          if v_pet_stun then v_stunned := true; v_stun_count := v_stun_count + 1; end if;
        else
          -- bleed / poison / burn: sát thương theo lượt, 3 lượt
          v_pdot_dmg := greatest(1, round(v_atk_now * v_pet_pct * 0.4 * v_pet_power))::int;
          v_pdot_left := 3;
          v_pdot_name := case v_pet_skill when 'bleed' then 'Chảy máu' when 'burn' then 'Thiêu đốt' else 'Độc' end;
        end if;
      end if;
      v_pet_dmg := round(greatest(1, (v_atk_now * v_pet_pct - p_enemy_def * (1 - v_pierce)) * v_gap_mult))::int;
      v_enemy_hp := greatest(0, v_enemy_hp - v_pet_dmg);
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'pet', 'pet_name', v_pet_name, 'damage', v_pet_dmg,
          'enemy_hp_left', v_enemy_hp, 'pet_skill', v_pet_used, 'heal', v_pet_heal, 'stun', v_pet_stun
        );
      end if;
      if v_pdot_left > 0 and v_enemy_hp > 0 then
        v_enemy_hp := greatest(0, v_enemy_hp - v_pdot_dmg);
        v_pdot_left := v_pdot_left - 1;
        if p_with_log then
          v_log := v_log || jsonb_build_object(
            'turn', v_turn, 'actor', 'character', 'skill', v_pdot_name || ' (pet)',
            'damage', v_pdot_dmg, 'crit', false, 'enemy_hp_left', v_enemy_hp, 'dot', true
          );
        end if;
      end if;
    end if;

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

    -- Ẩn Thân / chặn đòn (Khiên Băng, pet Hộ Thân) / Lướt Gió: đòn này của quái không trúng
    if v_vanish or v_block > 0 or (v_evade_left > 0 and random() < v_evade) then
      if v_vanish then v_vanish := false; elsif v_block > 0 then v_block := v_block - 1; end if;
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
          'damage', 0, 'character_hp_left', v_char_hp, 'blocked', true, 'enemy_hp_left', v_enemy_hp
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
                   * (1 - least(0.6, p_dmg_reduction + v_gear_red + least(3, v_guard_hits) * v_guard_step
                                   + case when v_drbuff_left > 0 then v_drbuff else 0 end)) * v_guardian;
    v_enemy_hit := round(v_enemy_dmg);
    -- Lá chắn Khiên Mana đỡ 50% mỗi đòn tới khi cạn
    v_absorbed := least(v_barrier, round(v_enemy_hit * 0.5)::int);
    v_barrier := v_barrier - v_absorbed;
    v_char_hp := greatest(0, v_char_hp - (v_enemy_hit - v_absorbed));
    v_dmg_taken := v_dmg_taken + v_enemy_hit - v_absorbed;
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
        'poison', v_poison_tick, 'regen', v_regen_e, 'shield', v_absorbed
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
