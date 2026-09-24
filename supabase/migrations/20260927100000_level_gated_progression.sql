-- Mở khoá theo cấp (phương án A): kỹ năng và thiên phú trải đều từ cấp 1 tới ~75
-- thay vì đủ hết ở cấp 14 (thiên phú) / 40 (kỹ năng).
--
-- Kỹ năng: chủ động Lv 1/12/25/45/60, bị động Lv 5/35; ô chủ động thứ 2 mở ở Lv8.
--   Ô trống tự lấp bằng skill mạnh nhất khi tạo nhân vật và khi lên cấp.
-- Thiên phú: 1 điểm ở Lv 6/14/22/30/50/65/75 + 1 điểm mỗi 25 tầng Tháp (tối đa 7);
--   ô lớn mở từ Lv20, ô trùm từ Lv40.
-- Nhân vật cũ: tháo skill chưa đủ cấp rồi lấp lại; tẩy cây miễn phí nếu vượt mức mới.
-- Mô phỏng Lv5-40: vùng đúng cấp gần như không đổi (skill có hồi chiêu nên đánh thường
-- chiếm phần lớn lượt) → không cần hạ chỉ số quái đầu game.

-- 1. Kỹ năng mở theo mốc cấp -------------------------------------------------------
update skills set unlock_level = v.lvl
from (values
  ('warrior_slash', 1), ('mage_fireball', 1), ('assassin_stab', 1), ('archer_shot', 1),
  ('warrior_knight', 12), ('mage_frost', 12), ('assassin_venom', 12), ('archer_pierce', 12),
  ('warrior_drain', 25), ('mage_shatter', 25), ('assassin_iai', 25), ('archer_aimed', 25),
  ('warrior_despair', 45), ('mage_inferno', 45), ('assassin_divine', 45), ('archer_fire', 45),
  ('warrior_holy', 60), ('mage_meteor', 60), ('assassin_execute', 60), ('archer_volley', 60),
  ('warrior_armor', 5), ('mage_shield', 5), ('assassin_critdmg', 5), ('archer_eagle', 5),
  ('warrior_will', 35), ('mage_focus', 35), ('assassin_shadow', 35), ('archer_reflex', 35)
) as v(key, lvl)
where skills.key = v.key;

-- 2. Giới hạn ô kỹ năng ----------------------------------------------------------------
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

  -- Ô chủ động thứ 2 mở ở cấp 8 (ô bị động mở cùng skill bị động đầu tiên, cấp 5)
  v_limit := case when v_skill_type = 'passive' then 1 when v_level >= 8 then 2 else 1 end;

  if v_count >= v_limit then
    raise exception 'Đã đủ số kỹ năng % được trang bị', v_skill_type;
  end if;

  return new;
end;
$$;

-- 3. Tự lấp ô khi tạo nhân vật / lên cấp ------------------------------------------------
-- Lấp ô kỹ năng còn trống bằng skill mạnh nhất đã mở (cấp mở cao nhất). Gọi khi tạo
-- nhân vật và khi lên cấp — lên cấp 5/8/12… tự có skill mới thay vì ô trống.
create or replace function public.fill_skill_slots(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_class_id uuid; v_level int; v_type text; v_free int;
begin
  select c.class_id, c.level into v_class_id, v_level from characters c where c.id = p_character_id;
  if not found then return; end if;

  foreach v_type in array array['active', 'passive'] loop
    v_free := case when v_type = 'passive' then 1 when v_level >= 8 then 2 else 1 end
      - (select count(*) from character_equipped_skills ces join skills s on s.id = ces.skill_id
         where ces.character_id = p_character_id and s.skill_type = v_type);
    continue when v_free <= 0;

    insert into character_equipped_skills (character_id, skill_id)
    select p_character_id, s.id from skills s
    where s.class_id = v_class_id and s.skill_type = v_type and s.unlock_level <= v_level
      and not exists (select 1 from character_equipped_skills ces
                      where ces.character_id = p_character_id and ces.skill_id = s.id)
    order by s.unlock_level desc
    limit v_free;
  end loop;
end;
$$;

revoke execute on function public.fill_skill_slots(uuid) from public, anon, authenticated;

create or replace function public.equip_starter_skills()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  perform fill_skill_slots(new.id);
  return new;
end;
$$;

-- Lên cấp: tự lấp ô kỹ năng mới mở
create or replace function public.fill_skill_slots_on_level_up()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  perform fill_skill_slots(new.id);
  return new;
end;
$$;

drop trigger if exists fill_skill_slots_on_level_up on characters;
create trigger fill_skill_slots_on_level_up
  after update of level on characters
  for each row when (new.level > old.level)
  execute function public.fill_skill_slots_on_level_up();

-- 4. Thiên phú theo cấp ---------------------------------------------------------------
create or replace function public.talent_points_total(p_level int, p_tower_best int)
returns int
language sql
immutable
as $$
  -- 1 điểm ở mỗi mốc cấp 6/14/22/30/50/65/75 + 1 điểm mỗi 25 tầng Tháp, tối đa 7
  select least(7,
    (select count(*)::int from unnest(array[6, 14, 22, 30, 50, 65, 75]) m where m <= p_level)
    + least(100, greatest(0, p_tower_best)) / 25);
$$;

create or replace function public.get_talent_state(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_tower int; v_total int; v_spent int;
begin
  select c.level, c.tower_best into v_level, v_tower
  from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  v_total := talent_points_total(v_level, v_tower);
  select coalesce(sum(n.cost), 0) into v_spent
  from character_talents ct join talent_nodes n on n.key = ct.node_key where ct.character_id = p_character_id;

  return jsonb_build_object(
    'total', v_total, 'spent', v_spent, 'available', v_total - v_spent,
    'learned', (select coalesce(jsonb_agg(ct.node_key), '[]'::jsonb) from character_talents ct where ct.character_id = p_character_id),
    'totals', get_talent_totals(p_character_id),
    'reset_cost', 30 * v_level,
    'level', v_level, 'notable_level', 20, 'keystone_level', 40
  );
end;
$$;

create or replace function public.learn_talent(p_character_id uuid, p_node_key text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_tower int; v_cost int; v_kind text; v_spent int;
begin
  select c.level, c.tower_best into v_level, v_tower
  from characters c where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select n.cost, n.kind into v_cost, v_kind from talent_nodes n where n.key = p_node_key;
  if not found or v_kind = 'start' then raise exception 'Không tìm thấy ô thiên phú này'; end if;

  -- Tầng ô mở theo cấp: ô lớn từ cấp 20, ô trùm từ cấp 40
  if v_kind = 'notable' and v_level < 20 then raise exception 'Ô lớn mở từ cấp 20'; end if;
  if v_kind = 'keystone' and v_level < 40 then raise exception 'Ô trùm mở từ cấp 40'; end if;

  if exists (select 1 from character_talents ct where ct.character_id = p_character_id and ct.node_key = p_node_key) then
    raise exception 'Đã học ô này rồi';
  end if;

  -- Phải kề ô đã học (hoặc kề tâm)
  if not exists (
    select 1 from talent_edges e
    where (e.a = p_node_key or e.b = p_node_key)
      and (case when e.a = p_node_key then e.b else e.a end) in (
        select 'origin' union all
        select ct.node_key from character_talents ct where ct.character_id = p_character_id)
  ) then
    raise exception 'Phải học ô liền kề trước';
  end if;

  select coalesce(sum(n.cost), 0) into v_spent
  from character_talents ct join talent_nodes n on n.key = ct.node_key where ct.character_id = p_character_id;
  if talent_points_total(v_level, v_tower) - v_spent < v_cost then
    raise exception 'Không đủ điểm thiên phú (cần % điểm)', v_cost;
  end if;

  insert into character_talents (character_id, node_key) values (p_character_id, p_node_key);
  return get_talent_state(p_character_id);
end;
$$;

-- 5. Dọn dữ liệu cũ ---------------------------------------------------------------------
-- Tháo skill chưa đủ cấp mới; dưới cấp 8 chỉ giữ 1 skill chủ động
delete from character_equipped_skills ces
using skills s, characters c
where s.id = ces.skill_id and c.id = ces.character_id and s.unlock_level > c.level;

delete from character_equipped_skills ces
where ces.id in (
  select x.id from (
    select ces2.id, row_number() over (partition by ces2.character_id order by s.unlock_level desc) rn
    from character_equipped_skills ces2
    join skills s on s.id = ces2.skill_id
    join characters c on c.id = ces2.character_id
    where s.skill_type = 'active' and c.level < 8
  ) x where x.rn > 1
);

select fill_skill_slots(c.id) from characters c;

-- Tẩy cây miễn phí nếu dùng quá số điểm mới hoặc đang giữ ô lớn/ô trùm chưa đủ cấp
do $$
declare
  r record;
  v_max_hp int;
begin
  for r in
    select c.id
    from characters c
    where exists (
      select 1 from character_talents ct join talent_nodes n on n.key = ct.node_key
      where ct.character_id = c.id
        and ((n.kind = 'notable' and c.level < 20) or (n.kind = 'keystone' and c.level < 40))
    )
    or (select coalesce(sum(n.cost), 0) from character_talents ct join talent_nodes n on n.key = ct.node_key
        where ct.character_id = c.id) > talent_points_total(c.level, c.tower_best)
  loop
    delete from character_talents ct where ct.character_id = r.id;
    select gs.max_hp into v_max_hp from get_character_stats(r.id) gs;
    update characters c set current_hp = least(c.current_hp, v_max_hp)
    where c.id = r.id and c.current_hp is not null;
  end loop;
end;
$$;
