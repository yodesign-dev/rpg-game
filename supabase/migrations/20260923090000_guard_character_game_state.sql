-- Chặn client tự sửa gold / level / exp / HP / AP ... qua REST.
--
-- RLS "own characters update" cho phép chủ nhân vật update CẢ DÒNG, nên từ
-- console trình duyệt có thể gọi
--   supabase.from('characters').update({ gold: 999999, level: 99 })
-- và thành công. Trigger dưới đây dùng danh sách TRẮNG: khi người gọi là
-- 'authenticated'/'anon', UPDATE chỉ được đổi `name` và `auto_allocate_stats`;
-- mọi cột khác (kể cả cột thêm sau này) đều bị khóa. Các RPC security definer
-- (resolve_dungeon_floor, use_item, buy_item, add_experience, apply_ap_regen,
-- ...) chạy dưới quyền owner nên current_user không phải 'authenticated' và
-- không bị chặn — giống guard_character_attributes.
--
-- INSERT: client chỉ được chọn user_id (RLS đã ép = auth.uid()), class_id,
-- name, auto_allocate_stats; các cột trạng thái game bị ép về mặc định.
--
-- Hồi AP trước đây do lib/ap-regen.ts update thẳng current_ap từ server
-- component (bằng session của người chơi) → giờ chuyển vào RPC apply_ap_regen,
-- tính hoàn toàn phía DB theo now().

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
      new.ap_regen_minutes := 10;
      new.last_ap_update := now();
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

drop trigger if exists guard_character_game_state on characters;
create trigger guard_character_game_state
  before insert or update on characters
  for each row execute function public.guard_character_game_state();

-- Hồi AP kiểu lazy: +1 AP mỗi ap_regen_minutes phút kể từ last_ap_update, tối
-- đa max_ap. Mốc last_ap_update chỉ tiến đúng số tick đã cộng để phần phút lẻ
-- không bị mất. Trả về AP hiện tại và số phút tới lần hồi kế tiếp (null nếu
-- AP đã đầy). Tên cột trả về có tiền tố out_ để tránh lỗi 42702 (trùng tên với
-- cột current_ap của bảng characters).
create or replace function public.apply_ap_regen(p_character_id uuid)
returns table(out_current_ap int, out_next_ap_minutes int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_current_ap int; v_max_ap int; v_regen_minutes int; v_last_update timestamptz;
  v_elapsed_minutes int; v_ticks int;
  v_next int := null;
begin
  select c.user_id, c.current_ap, c.max_ap, greatest(1, c.ap_regen_minutes), c.last_ap_update
    into v_owner_user_id, v_current_ap, v_max_ap, v_regen_minutes, v_last_update
  from characters c where c.id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  v_elapsed_minutes := greatest(0, floor(extract(epoch from (now() - v_last_update)) / 60))::int;
  v_ticks := v_elapsed_minutes / v_regen_minutes;

  if v_ticks > 0 and v_current_ap < v_max_ap then
    v_current_ap := least(v_max_ap, v_current_ap + v_ticks);

    update characters c
    set current_ap = v_current_ap,
        last_ap_update = c.last_ap_update + make_interval(mins => v_ticks * v_regen_minutes)
    where c.id = p_character_id;
  end if;

  if v_current_ap < v_max_ap then
    v_next := v_regen_minutes - (v_elapsed_minutes % v_regen_minutes);
  end if;

  return query select v_current_ap, v_next;
end;
$$;
