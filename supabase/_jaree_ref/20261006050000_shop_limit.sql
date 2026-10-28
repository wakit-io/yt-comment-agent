-- 계정별 추가 상점 사용권. 운영자에게는 조회만 허용한다.
create table if not exists public.desk_account_entitlements(
 user_id uuid primary key references auth.users(id) on delete cascade,
 extra_shop_slots integer not null default 0 check(extra_shop_slots between 0 and 100),
 expires_at timestamptz,
 updated_at timestamptz not null default now()
);
alter table public.desk_account_entitlements enable row level security;
revoke all on public.desk_account_entitlements from anon,authenticated;
grant select on public.desk_account_entitlements to authenticated;
drop policy if exists account_entitlements_read on public.desk_account_entitlements;
create policy account_entitlements_read on public.desk_account_entitlements for select to authenticated using(user_id=auth.uid());

create or replace function public.desk_shop_quota() returns jsonb
language plpgsql security definer set search_path='' as $$
declare extra integer; owned integer; maximum integer;
begin
 if auth.uid() is null then raise exception '로그인 필요' using errcode='42501'; end if;
 select extra_shop_slots into extra from public.desk_account_entitlements where user_id=auth.uid() and (expires_at is null or expires_at>now());
 select count(*) into owned from public.desk_shop_members where user_id=auth.uid() and role='owner';
 maximum=1+coalesce(extra,0);
 return jsonb_build_object('owned_shops',owned,'shop_limit',maximum,'remaining',greatest(maximum-owned,0),'can_create',owned<maximum,'extra_shop_slots',coalesce(extra,0));
end $$;
revoke all on function public.desk_shop_quota() from public;
grant execute on function public.desk_shop_quota() to authenticated;

create or replace function public.desk_create_shop(shop_slug text,shop_name text)
returns public.desk_shops language plpgsql security definer set search_path='' as $$
declare s public.desk_shops; quota jsonb;
begin
 if auth.uid() is null then raise exception '로그인 필요' using errcode='42501'; end if;
 if shop_slug is null or shop_name is null or shop_slug !~ '^[a-z0-9][a-z0-9-]{2,39}$' or length(trim(shop_name)) not between 1 and 100 then raise exception '잘못된 상점 정보'; end if;
 -- 동일 계정의 생성 요청을 직렬화한다. 대기 후 다시 세어 동시 생성도 제한한다.
 perform 1 from auth.users where id=auth.uid() for update;
 if not found then raise exception '로그인 필요' using errcode='42501'; end if;
 quota=public.desk_shop_quota();
 if not (quota->>'can_create')::boolean then
  raise exception '상점 생성 한도에 도달했습니다. 기본 계정은 상점 1개까지이며, 추가 상점 사용권이 필요합니다.' using errcode='P0001',detail='SHOP_LIMIT_REACHED';
 end if;
 insert into public.desk_shops(slug,name) values(shop_slug,trim(shop_name)) returning * into s;
 insert into public.desk_shop_members(shop_id,user_id,role) values(s.id,auth.uid(),'owner');
 insert into public.desk_config(shop_id,k,v) values
 (s.id,'biz_name',trim(shop_name)),(s.id,'biz_tagline','당신을 위한 특별한 공간'),
 (s.id,'description','우리 상점을 소개해주세요.'),(s.id,'accent','#4f46e5'),(s.id,'hours','예약제로 운영합니다');
 return s;
end $$;
revoke all on function public.desk_create_shop(text,text) from public;
grant execute on function public.desk_create_shop(text,text) to authenticated;
