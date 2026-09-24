-- Icon kỹ năng (pixel art Raven Fantasy Icons — bản free: chỉ dùng cho game miễn phí, không
-- microtransaction/quảng cáo trả tiền) + khung chân dung mở bằng thành tích (frames pack của
-- Batareya). Khung là đồ trang trí: guard kiểm tra điều kiện mở khi người chơi tự đổi.

-- 1. Icon kỹ năng ---------------------------------------------------------------------------
update skills set icon = '/skills/' || key || '.png'
where key in ('warrior_slash', 'warrior_knight', 'warrior_drain', 'warrior_despair', 'warrior_holy', 'warrior_armor', 'warrior_will', 'mage_fireball', 'mage_frost', 'mage_shatter', 'mage_inferno', 'mage_meteor', 'mage_shield', 'mage_focus', 'assassin_stab', 'assassin_venom', 'assassin_iai', 'assassin_divine', 'assassin_execute', 'assassin_critdmg', 'assassin_shadow', 'archer_shot', 'archer_pierce', 'archer_aimed', 'archer_fire', 'archer_volley', 'archer_eagle', 'archer_reflex');

-- 2. Khung chân dung ------------------------------------------------------------------------
alter table characters add column if not exists frame text;
alter table characters drop constraint if exists characters_frame_key;
alter table characters
  add constraint characters_frame_key check (frame in ('wood', 'bronze', 'silver', 'gold', 'bloom', 'engraved', 'moss'));

-- Điều kiện mở khung chân dung — khớp FRAMES trong lib/frames.ts
create or replace function public.frame_unlocked(
  p_frame text, p_level int, p_tower_best int, p_legendary_found int, p_boss_kills int
)
returns boolean
language sql
immutable
as $$
  select case p_frame
    when 'wood' then true
    when 'bronze' then p_level >= 20
    when 'silver' then p_level >= 40 or p_tower_best >= 30
    when 'gold' then p_level >= 60 or p_tower_best >= 60
    when 'bloom' then p_legendary_found >= 1
    when 'moss' then p_boss_kills >= 50
    when 'engraved' then p_tower_best >= 100
    else false
  end;
$$;

create or replace function public.guard_character_game_state()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.level := 1;
      new.exp := 0;
      new.exp_to_next := 100;
      new.gold := 100;
      new.current_chapter := 1;
      new.current_hp := null;
      new.current_ap := 100;
      new.max_ap := 100;
      new.ap_regen_minutes := 1;
      new.last_ap_update := now();
      new.last_hp_update := now();
      new.created_at := now();
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame') then
      raise exception 'Chỉ được đổi tên, chân dung, khung và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    elsif new.frame is distinct from old.frame and new.frame is not null
          and not frame_unlocked(new.frame, new.level, new.tower_best, new.legendary_found, new.boss_kills) then
      raise exception 'Chưa mở khóa khung này';
    end if;
  end if;
  return new;
end;
$$;

-- 3. Bảng xếp hạng trả thêm chân dung + khung -------------------------------------------------
drop function if exists public.get_leaderboard(text);

create or replace function public.get_leaderboard(p_sort text)
returns table(
  out_rank int, out_character_id uuid, out_name text, out_class_key text, out_class_name text,
  out_level int, out_power int, out_boss_kills int, out_kills int, out_tower_best int, out_title text,
  out_portrait text, out_frame text
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with base as (
    select c.id, c.name, cl.key as class_key, cl.name as class_name, c.level, c.exp,
           character_power(c.id) as power, c.boss_kills, c.kills, c.tower_best,
           t.emoji || ' ' || t.name as title, c.portrait, c.frame
    from characters c
    join classes cl on cl.id = c.class_id
    left join titles t on t.key = c.title_key
  )
  select (row_number() over (order by
            case p_sort when 'power' then b.power when 'boss_kills' then b.boss_kills
                        when 'tower' then b.tower_best else b.level end desc,
            case p_sort when 'level' then b.exp else b.level end desc,
            b.name))::int,
         b.id, b.name, b.class_key, b.class_name, b.level, b.power, b.boss_kills, b.kills, b.tower_best, b.title,
         b.portrait, b.frame
  from base b
  order by 1
  limit 50;
$$;
