-- Chân dung nhân vật: 10 mẫu mỗi class (public/portraits/<class>_<n>.png, pixel art từ pack
-- "500+ Free Pixel-art Fantasy Character Pack" của Batareya — pack gốc không đưa vào repo).
-- null = mẫu 1 của class. Client được tự đổi (giống tên / chế độ tự cộng điểm).

alter table characters add column if not exists portrait text;
alter table characters drop constraint if exists characters_portrait_format;
alter table characters
  add constraint characters_portrait_format check (portrait ~ '^(warrior|mage|archer|assassin)_([1-9]|10)$');

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
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats' - 'portrait')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats' - 'portrait') then
      raise exception 'Chỉ được đổi tên, chân dung và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    end if;
  end if;
  return new;
end;
$$;
