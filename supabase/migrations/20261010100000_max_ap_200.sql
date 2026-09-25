-- Nâng AP tối đa 100 → 200 cho mọi nhân vật (nhân vật mới cũng bắt đầu đầy 200 AP).
-- AP đang có giữ nguyên, hồi tiếp +1/phút tới mức mới.

alter table characters alter column max_ap set default 200;
update characters set max_ap = 200 where max_ap < 200;

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
      new.current_ap := 200;
      new.max_ap := 200;
      new.ap_regen_minutes := 1;
      new.last_ap_update := now();
      new.last_hp_update := now();
      new.created_at := now();
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame' - 'auto_potion')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame' - 'auto_potion') then
      raise exception 'Chỉ được đổi tên, chân dung, khung và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    elsif new.frame is distinct from old.frame and new.frame is not null
          and not frame_unlocked(new.frame, new.level, new.tower_best, new.legendary_found, new.boss_kills) then
      raise exception 'Chưa mở khóa khung này';
    end if;
  end if;
  return new;
end;
$$;
