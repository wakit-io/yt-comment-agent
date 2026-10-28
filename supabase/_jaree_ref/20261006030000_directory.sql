-- 공개 포트폴리오: 공개 상점과 허용된 브랜드/서비스 정보만 반환한다.
create or replace function public.desk_public_directory(search_text text default '', only_bookable boolean default false, page_number integer default 1, page_size integer default 12)
returns jsonb language sql stable set search_path=public as $$
 with stores as (
  select s.id,s.slug,s.name,s.created_at,
   coalesce(c.brand,'{}'::jsonb) as brand,
   coalesce(v.services,'[]'::jsonb) as services,
   coalesce(v.bookable,false) as bookable,coalesce(v.search_names,'') as search_names
  from desk_shops s
  left join lateral(select jsonb_object_agg(k,v) as brand from desk_config where shop_id=s.id and k in ('biz_name','biz_tagline','description','logo_url','hero_url','accent','address')) c on true
  left join lateral(select jsonb_agg(jsonb_build_object('name',name,'duration_minutes',duration_minutes,'booking_enabled',booking_enabled) order by name) as services,bool_or(booking_enabled) as bookable,string_agg(name,' ') as search_names from desk_services where shop_id=s.id and active) v on true
  where s.published
 ), matches as (
  select * from stores where (not only_bookable or bookable) and (
   coalesce(search_text,'')='' or strpos(lower(name||' '||slug||' '||coalesce(brand->>'biz_name','')||' '||coalesce(brand->>'biz_tagline','')||' '||coalesce(brand->>'description','')||' '||coalesce(brand->>'address','')||' '||search_names),lower(search_text))>0
  )
 ), paged as (
  select jsonb_build_object('slug',slug,'name',name,'brand',brand,'services',services,'booking_available',bookable,'url','/@'||slug,'booking_url','/@'||slug||'#book') as card
  from matches order by created_at desc,slug limit greatest(1,least(24,page_size)) offset ((greatest(1,page_number)::bigint-1)*greatest(1,least(24,page_size)))
 )
 select jsonb_build_object('shops',coalesce((select jsonb_agg(card) from paged),'[]'::jsonb),'total',(select count(*) from matches),'page',greatest(1,page_number),'page_size',greatest(1,least(24,page_size)))
$$;
revoke all on function public.desk_public_directory(text,boolean,integer,integer) from public,anon,authenticated;
grant execute on function public.desk_public_directory(text,boolean,integer,integer) to service_role;
