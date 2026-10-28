-- 공개 포트폴리오: 공개 상점과 허용된 브랜드/서비스 정보만 반환한다.
drop function if exists public.desk_public_directory(text,boolean,integer,integer);
create or replace function public.desk_public_directory(search_text text default '', only_bookable boolean default false, page_number integer default 1, page_size integer default 12, region_filter text default '', district_filter text default '')
returns jsonb language sql stable set search_path=public as $$
 with stores as (
  select s.id,s.slug,s.name,s.created_at,
   coalesce(c.brand,'{}'::jsonb) as brand,
   coalesce(v.services,'[]'::jsonb) as services,
   coalesce(v.bookable,false) as bookable,coalesce(v.search_names,'') as search_names
  from desk_shops s
  left join lateral(select jsonb_object_agg(k,v) as brand from desk_config where shop_id=s.id and k in ('biz_name','biz_tagline','description','logo_url','hero_url','accent','address','region','district','place_name','address_detail','map_url')) c on true
  left join lateral(select jsonb_agg(jsonb_build_object('name',name,'duration_minutes',duration_minutes,'booking_enabled',booking_enabled) order by name) as services,bool_or(booking_enabled) as bookable,string_agg(name,' ') as search_names from desk_services where shop_id=s.id and active) v on true
  where s.published
 ), matches as (
  select * from stores where (coalesce(region_filter,'')='' or brand->>'region'=region_filter) and (coalesce(district_filter,'')='' or brand->>'district'=district_filter) and (not only_bookable or bookable) and (
   coalesce(search_text,'')='' or strpos(lower(name||' '||slug||' '||coalesce(brand->>'biz_name','')||' '||coalesce(brand->>'biz_tagline','')||' '||coalesce(brand->>'description','')||' '||coalesce(brand->>'address','')||' '||coalesce(brand->>'region','')||' '||coalesce(brand->>'district','')||' '||coalesce(brand->>'place_name','')||' '||search_names),lower(search_text))>0
  )
 ), paged as (
  select jsonb_build_object('slug',slug,'name',name,'brand',brand,'location',jsonb_build_object('region',coalesce(brand->>'region',''),'district',coalesce(brand->>'district',''),'address',coalesce(brand->>'address',''),'address_detail',coalesce(brand->>'address_detail',''),'place_name',coalesce(brand->>'place_name',''),'map_url',coalesce(brand->>'map_url','')),'services',services,'booking_available',bookable,'url','/@'||slug,'booking_url','/@'||slug||'#book') as card
  from matches order by created_at desc,slug limit greatest(1,least(24,page_size)) offset ((greatest(1,page_number)::bigint-1)*greatest(1,least(24,page_size)))
 )
 select jsonb_build_object('shops',coalesce((select jsonb_agg(card) from paged),'[]'::jsonb),'total',(select count(*) from matches),'page',greatest(1,page_number),'page_size',greatest(1,least(24,page_size)))
$$;
revoke all on function public.desk_public_directory(text,boolean,integer,integer,text,text) from public,anon,authenticated;
grant execute on function public.desk_public_directory(text,boolean,integer,integer,text,text) to service_role;

-- 기존 주소에서 광역 지역만 이관. 구/군 정보는 운영자가 정확히 설정한다.
insert into public.desk_config(shop_id,k,v)
select shop_id,'region',substring(v from '^(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)')
from public.desk_config where k='address' and v ~ '^(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)(특별|광역|자치|시|도| |·|$)'
on conflict(shop_id,k) do nothing;

create or replace function public.desk_public_regions() returns jsonb language sql stable set search_path=public as $$
 with places as (
  select r.v as region,coalesce(d.v,'') as district
  from desk_shops s join desk_config r on r.shop_id=s.id and r.k='region' and r.v<>''
  left join desk_config d on d.shop_id=s.id and d.k='district'
  where s.published
 ), groups as (select region,district,count(*) as shops from places group by region,district)
 select coalesce(jsonb_agg(jsonb_build_object('region',region,'district',district,'shops',shops) order by region,district),'[]'::jsonb) from groups
$$;
revoke all on function public.desk_public_regions() from public,anon,authenticated;
grant execute on function public.desk_public_regions() to service_role;
