-- Khóa các lỗ hổng cheat còn lại (audit bảo mật 2026-09-23).
--
-- 1. add_experience là security definer và client gọi được trực tiếp:
--      supabase.rpc('add_experience', { p_character_id, p_exp_gained: 99999999 })
--    → lên cấp vô hạn + điểm chỉ số. Chỉ resolve_dungeon_floor / explore_zone
--    (chạy dưới quyền owner) cần gọi hàm này → revoke khỏi client.
-- 2. inventory: policy insert/update cho phép client tự thêm vật phẩm bất kỳ
--    (kể cả legendary, rolled_atk = 99999, quantity = 99999) và mặc mọi món
--    cùng lúc (get_character_stats cộng mọi dòng equipped = true). Bỏ quyền
--    ghi trực tiếp; mặc/gỡ đồ đi qua RPC equip_item / unequip_item có kiểm tra
--    khớp trang bị.
-- 3. dungeon_runs / character_pets / character_quests: client tự insert được
--    (vd. dòng 'cleared' giả để mở khóa tầng boss). Bỏ quyền ghi trực tiếp.
-- 4. resolve_dungeon_floor không kiểm tra tầng đã mở khóa → thêm kiểm tra.
-- 5. character_equipped_skills: client insert được skill của class khác, chưa
--    đủ cấp, hoặc vượt giới hạn 2 chủ động / 1 bị động → trigger kiểm tra.
-- 6. Dọn dữ liệu đã bị lợi dụng (đồ mặc sai khớp / trùng khớp, skill sai).

-- 1. add_experience ------------------------------------------------------------
revoke execute on function public.add_experience(uuid, int) from public, anon, authenticated;

-- apply_ap_regen đã được thay bằng apply_regen (lib/regen.ts) — bỏ cho gọn bề mặt tấn công.
drop function if exists public.apply_ap_regen(uuid);

-- 2 + 3. Bỏ quyền ghi trực tiếp -------------------------------------------------
drop policy if exists "own inventory insert" on inventory;
drop policy if exists "own inventory update" on inventory;
drop policy if exists "own dungeon_runs insert" on dungeon_runs;
drop policy if exists "own dungeon_runs update" on dungeon_runs;
drop policy if exists "own pets insert" on character_pets;
drop policy if exists "own pets update" on character_pets;
drop policy if exists "own character_quests insert" on character_quests;
drop policy if exists "own character_quests update" on character_quests;

revoke insert, update, delete on table inventory, dungeon_runs, character_pets, character_quests
  from anon, authenticated;

-- Khớp trang bị hợp lệ cho từng loại item (dùng chung cho equip_item và dọn dữ liệu).
create or replace function public.equip_slot_allowed(p_item_slot text, p_hand text, p_equip_slot text)
returns boolean
language sql
immutable
as $$
  select case
    when p_item_slot in ('weapon', 'shield') then
      case when p_hand = 'two_hand' then p_equip_slot = 'both_arms'
           else p_equip_slot in ('l_arm', 'r_arm') end
    when p_item_slot = 'ring' then p_equip_slot in ('ring_1', 'ring_2')
    when p_item_slot in ('head', 'chest', 'belt', 'amulet', 'boot') then p_equip_slot = p_item_slot
    else false
  end;
$$;

-- Mặc 1 món vào khớp p_slot, tự gỡ món đang chiếm khớp đó (vũ khí 2 tay chiếm
-- cả l_arm lẫn r_arm). Trả về id các dòng vừa bị gỡ để client cập nhật UI.
create or replace function public.equip_item(p_character_id uuid, p_inventory_id uuid, p_slot text)
returns uuid[]
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_item_slot text; v_item_hand text; v_item_type text;
  v_clear text[];
  v_unequipped uuid[];
begin
  select c.user_id into v_owner_user_id
  from characters c where c.id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select i.slot, i.hand, i.type into v_item_slot, v_item_hand, v_item_type
  from inventory inv join items i on i.id = inv.item_id
  where inv.id = p_inventory_id and inv.character_id = p_character_id
  for update of inv;

  if not found then raise exception 'Không tìm thấy vật phẩm trong túi đồ'; end if;

  if v_item_type not in ('weapon', 'armor')
     or not equip_slot_allowed(v_item_slot, v_item_hand, p_slot) then
    raise exception 'Không thể mặc vật phẩm này vào vị trí đó';
  end if;

  v_clear := case
    when p_slot = 'both_arms' then array['l_arm', 'r_arm', 'both_arms']
    when p_slot in ('l_arm', 'r_arm') then array[p_slot, 'both_arms']
    else array[p_slot]
  end;

  with cleared as (
    update inventory inv
    set equipped = false, equip_slot = null
    where inv.character_id = p_character_id and inv.equipped
      and inv.equip_slot = any(v_clear) and inv.id <> p_inventory_id
    returning inv.id
  )
  select coalesce(array_agg(cleared.id), '{}') into v_unequipped from cleared;

  update inventory inv
  set equipped = true, equip_slot = p_slot
  where inv.id = p_inventory_id;

  return v_unequipped;
end;
$$;

create or replace function public.unequip_item(p_character_id uuid, p_inventory_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  update inventory inv
  set equipped = false, equip_slot = null
  where inv.id = p_inventory_id and inv.character_id = p_character_id;

  if not found then raise exception 'Không tìm thấy vật phẩm trong túi đồ'; end if;
end;
$$;

-- 4. resolve_dungeon_floor: thêm kiểm tra tầng đã mở khóa -----------------------
create or replace function public.resolve_dungeon_floor(p_character_id uuid, p_dungeon_floor_id uuid)
returns table(win boolean, remaining_hp integer, exp_gained integer, gold_gained integer, item_dropped text, leveled_up boolean, new_level integer, combat_log jsonb, timed_out boolean)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  -- Nhân vật
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int;
  v_max_hp int; v_char_atk int; v_char_def int;
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  -- Skill
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_lifesteal numeric; v_crit_chance numeric;
  -- Tầng / quái
  v_dungeon_id uuid; v_ap_cost int; v_enemy_name text; v_enemy_level int;
  v_enemy_hp int; v_enemy_atk int; v_enemy_def int;
  v_reward_exp int; v_reward_gold int; v_drop_item_id uuid; v_drop_rate numeric;
  v_floor_number int;
  -- Scaling
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  -- Kết quả trận
  v_win boolean; v_timed_out boolean; v_hp_left int; v_log jsonb;
  v_final_hp int;
  v_was_full_ap boolean;
  v_exp_gained int := 0; v_gold_gained int := 0; v_item_dropped text := null;
  v_leveled_up boolean := false; v_new_level int;
begin
  -- 1. Quyền + hồi phục theo thời gian trước khi đọc HP/AP
  select user_id into v_owner_user_id from characters where id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select level, current_hp, current_ap, max_ap
    into v_level, v_current_hp, v_current_ap, v_max_ap
  from characters where id = p_character_id for update;

  -- 2. Chỉ số tổng hợp: class + cấp + điểm chỉ số + trang bị (kể cả affix roll)
  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_current_hp := coalesce(v_current_hp, v_max_hp);

  if v_current_hp <= 0 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi vào dungeon';
  end if;

  -- 3. Tầng dungeon đang đánh
  select df.dungeon_id, df.floor_number, df.enemy_name, df.enemy_level,
         df.enemy_hp, df.enemy_atk, df.enemy_def, df.reward_exp, df.reward_gold,
         df.drop_item_id, df.drop_rate, d.ap_cost
    into v_dungeon_id, v_floor_number, v_enemy_name, v_enemy_level,
         v_enemy_hp, v_enemy_atk, v_enemy_def, v_reward_exp, v_reward_gold,
         v_drop_item_id, v_drop_rate, v_ap_cost
  from dungeon_floors df join dungeons d on d.id = df.dungeon_id
  where df.id = p_dungeon_floor_id;

  if not found then raise exception 'Không tìm thấy tầng dungeon'; end if;

  -- Chỉ được đánh tầng đã mở khóa: tầng 1, hoặc đã qua tầng ngay trước đó.
  -- (Trước đây chỉ UI khóa → gọi RPC thẳng là đánh được boss tầng cuối.)
  if v_floor_number > 1 and not exists (
    select 1 from dungeon_runs dr
    where dr.character_id = p_character_id and dr.dungeon_id = v_dungeon_id
      and dr.status = 'cleared' and dr.current_floor >= v_floor_number - 1
  ) then
    raise exception 'Tầng này chưa mở khóa (cần qua tầng % trước)', v_floor_number - 1;
  end if;

  if v_current_ap < v_ap_cost then
    raise exception 'Không đủ AP để vào tầng này (cần % AP)', v_ap_cost;
  end if;

  -- 4. Skill + bị động, cộng dồn chí mạng (AGI/DEX + affix, chặn 75%) và hút máu
  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;

  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;

  -- 5. Hệ số scaling theo chênh lệch cấp độ
  select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
  from calculate_combat_scaling(v_level, v_enemy_level);

  -- 6. Mô phỏng trận đấu
  select f.out_win, f.out_timed_out, f.out_hp_left, f.out_log
    into v_win, v_timed_out, v_hp_left, v_log
  from simulate_fight(
    v_char_atk, v_char_def, v_current_hp, v_max_hp,
    v_crit_chance, v_lifesteal, v_dmg_reduction,
    v_a1_name, v_a1_power, v_a2_name, v_a2_power,
    v_enemy_name, v_enemy_hp, v_enemy_atk, v_enemy_def,
    v_damage_multiplier, true
  ) f;

  v_final_hp := case when v_win then v_hp_left else greatest(1, v_hp_left) end;

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
      perform grant_drop(p_character_id, v_drop_item_id);
      select key into v_item_dropped from items where id = v_drop_item_id;
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


-- 5. Skill trang bị: đúng class, đủ cấp, không trùng, tối đa 2 chủ động + 1 bị động.
-- security definer để khóa được dòng characters (tránh 2 request song song cùng
-- vượt giới hạn); quyền sở hữu nhân vật đã do RLS "own equipped skills insert" kiểm.
create or replace function public.guard_equipped_skill()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_class_id uuid; v_level int;
  v_skill_class_id uuid; v_unlock_level int; v_skill_type text;
  v_count int; v_limit int;
begin
  select c.class_id, c.level into v_class_id, v_level
  from characters c where c.id = new.character_id for update;

  select s.class_id, s.unlock_level, s.skill_type into v_skill_class_id, v_unlock_level, v_skill_type
  from skills s where s.id = new.skill_id;

  if v_skill_class_id is distinct from v_class_id then
    raise exception 'Kỹ năng này không thuộc class của bạn';
  end if;

  if v_level < v_unlock_level then
    raise exception 'Cần đạt cấp % để dùng kỹ năng này', v_unlock_level;
  end if;

  if exists (
    select 1 from character_equipped_skills ces
    where ces.character_id = new.character_id and ces.skill_id = new.skill_id
  ) then
    raise exception 'Kỹ năng đã được trang bị';
  end if;

  select count(*) into v_count
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = new.character_id and s.skill_type = v_skill_type;

  v_limit := case when v_skill_type = 'passive' then 1 else 2 end;

  if v_count >= v_limit then
    raise exception 'Đã đủ số kỹ năng % được trang bị', v_skill_type;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_equipped_skill on character_equipped_skills;
create trigger guard_equipped_skill
  before insert on character_equipped_skills
  for each row execute function public.guard_equipped_skill();

revoke update on table character_equipped_skills from anon, authenticated;

-- Tên nhân vật: 1-20 ký tự như form tạo nhân vật (not valid: không kiểm dữ liệu cũ).
alter table characters drop constraint if exists characters_name_length;
alter table characters
  add constraint characters_name_length check (char_length(btrim(name)) between 1 and 20) not valid;

-- 6. Dọn dữ liệu đã bị lợi dụng ---------------------------------------------------
-- Đồ đang mặc sai khớp (hoặc equipped mà không có khớp)
update inventory inv
set equipped = false, equip_slot = null
from items i
where i.id = inv.item_id and inv.equipped
  and (inv.equip_slot is null or i.type not in ('weapon', 'armor')
       or not equip_slot_allowed(i.slot, i.hand, inv.equip_slot));

-- Nhiều món cùng 1 khớp → giữ món mới nhất
update inventory inv
set equipped = false, equip_slot = null
from (
  select x.id, row_number() over (partition by x.character_id, x.equip_slot order by x.acquired_at desc) as rn
  from inventory x where x.equipped
) d
where d.id = inv.id and d.rn > 1;

-- Vũ khí 2 tay cùng lúc với đồ ở l_arm / r_arm → gỡ đồ 1 tay
update inventory inv
set equipped = false, equip_slot = null
where inv.equipped and inv.equip_slot in ('l_arm', 'r_arm')
  and exists (
    select 1 from inventory b
    where b.character_id = inv.character_id and b.equipped and b.equip_slot = 'both_arms'
  );

-- Skill sai class / chưa đủ cấp
delete from character_equipped_skills ces
using characters c, skills s
where c.id = ces.character_id and s.id = ces.skill_id
  and (s.class_id <> c.class_id or c.level < s.unlock_level);

-- Skill trùng hoặc vượt giới hạn (giữ theo thứ tự s.key như lúc vào trận)
delete from character_equipped_skills ces
using (
  select x.id,
         row_number() over (partition by x.character_id, x.skill_id order by x.id) as dup_rn,
         dense_rank() over (partition by x.character_id, s.skill_type order by s.key) as type_rank,
         s.skill_type
  from character_equipped_skills x join skills s on s.id = x.skill_id
) r
where r.id = ces.id
  and (r.dup_rn > 1 or r.type_rank > case when r.skill_type = 'passive' then 1 else 2 end);
