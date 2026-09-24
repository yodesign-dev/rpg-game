-- Giới hạn điểm thiên phú tối đa 7 điểm / nhân vật (trước đây ~60).
--
-- Vẫn nhận 1 điểm mỗi 2 cấp + 1 điểm mỗi 10 tầng Tháp, nhưng dừng ở 7 → phải chọn
-- build thật sự. Ô trùm giảm từ 3 → 2 điểm để 7 điểm vừa đủ đi hết một nhánh tới
-- ô trùm (nhỏ 1 + nhỏ 1 + lớn 2 + nhỏ 1 + trùm 2 = 7).
--
-- Nhân vật đang dùng quá 7 điểm được tẩy cây miễn phí (không trừ vàng).

update talent_nodes set cost = 2 where kind = 'keystone';

create or replace function public.talent_points_total(p_level int, p_tower_best int)
returns int
language sql
immutable
as $$ select least(7, (greatest(1, p_level) / 2) + (least(100, greatest(0, p_tower_best)) / 10)); $$;

do $$
declare
  r record;
  v_max_hp int;
begin
  for r in
    select c.id
    from characters c
    join character_talents ct on ct.character_id = c.id
    join talent_nodes n on n.key = ct.node_key
    group by c.id, c.level, c.tower_best
    having sum(n.cost) > talent_points_total(c.level, c.tower_best)
  loop
    delete from character_talents ct where ct.character_id = r.id;
    select gs.max_hp into v_max_hp from get_character_stats(r.id) gs;
    update characters c set current_hp = least(c.current_hp, v_max_hp)
    where c.id = r.id and c.current_hp is not null;
  end loop;
end;
$$;
