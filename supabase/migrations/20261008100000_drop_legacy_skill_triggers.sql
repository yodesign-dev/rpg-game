-- Tạo nhân vật lỗi "Kỹ năng đã được trang bị": trên production còn 2 trigger cũ tạo tay (không có
-- trong migrations) chạy song song với bản hiện tại:
--   - trg_auto_equip_skills (characters, after insert) trang bị lại kỹ năng khởi đầu mà
--     equip_starter_skills → fill_skill_slots vừa trang bị → guard_equipped_skill báo trùng.
--   - trg_check_equip_limit (character_equipped_skills) trùng việc với guard_equipped_skill.
drop trigger if exists trg_auto_equip_skills on public.characters;
drop function if exists public.auto_equip_starting_skills();
drop trigger if exists trg_check_equip_limit on public.character_equipped_skills;
drop function if exists public.check_equip_limit();
