-- Xoá nhân vật qua RPC: role authenticated không có quyền DELETE trên characters (bị thu hồi như
-- các bảng game khác), nên nút "Xoá nhân vật" báo "permission denied for table characters".
-- Hàm chạy dưới quyền owner, chỉ xoá nhân vật của chính người gọi; các bảng con xoá theo cascade,
-- activity_feed giữ lại (character_id → null).
create or replace function public.delete_character(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  delete from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không tìm thấy nhân vật hoặc không có quyền xoá'; end if;
end;
$$;

revoke execute on function public.delete_character(uuid) from public, anon;
grant execute on function public.delete_character(uuid) to authenticated;
