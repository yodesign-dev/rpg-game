-- AP hồi nhanh hơn: 5 phút/điểm → 1 phút/điểm (đầy 100 AP trong ~1h40).
alter table characters alter column ap_regen_minutes set default 1;
update characters set ap_regen_minutes = 1;

-- Trigger chặn client ép giá trị này khi tạo nhân vật → cập nhật theo.
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
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats') then
      raise exception 'Chỉ được đổi tên và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    end if;
  end if;
  return new;
end;
$$;

