-- Project này KHÔNG tự cấp quyền cho bảng mới tạo (default privileges của
-- schema public không grant cho anon/authenticated), nên RLS policy có
-- đúng cũng vô ích: PostgREST trả rỗng/lỗi permission. Hậu quả: trang Thám
-- Hiểm không thấy vùng nào, tab chế tạo không thấy công thức nào.
-- Bảng mới sau này nhớ grant tường minh như dưới.
grant select on table zones, zone_enemies, zone_drops, recipes, recipe_ingredients to anon, authenticated;
grant select on table explore_runs to authenticated;
