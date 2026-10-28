-- 예약 조회권: 전화번호를 기준으로 회원 예약을 자동 연결하지 않는다.
create table if not exists public.desk_booking_access(
 booking_id uuid primary key references public.desk_bookings(id) on delete cascade,
 user_id uuid references auth.users(id) on delete set null,
 guest_token_hash text not null check(guest_token_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz not null default now()
);
create index if not exists desk_booking_access_user on public.desk_booking_access(user_id);
alter table public.desk_booking_access enable row level security;
revoke all on public.desk_booking_access from anon,authenticated;
-- 고객 상세는 서버에서 허용된 필드만 조회해 반환한다. 운영자도 조회권을 수정할 수 없다.
create or replace function public.desk_insert_customer_booking(booking_data jsonb, customer_user uuid, token_hash text)
returns public.desk_bookings language plpgsql set search_path='' as $$
declare b public.desk_bookings;
begin
 insert into public.desk_bookings(shop_id,customer_id,customer_name,phone,service,service_id,date,time,message,source,status)
 values((booking_data->>'shop_id')::uuid,(booking_data->>'customer_id')::uuid,booking_data->>'customer_name',booking_data->>'phone',booking_data->>'service',(booking_data->>'service_id')::uuid,(booking_data->>'date')::date,booking_data->>'time',booking_data->>'message','web','requested') returning * into b;
 insert into public.desk_booking_access(booking_id,user_id,guest_token_hash) values(b.id,customer_user,token_hash);
 return b;
end $$;
revoke all on function public.desk_insert_customer_booking(jsonb,uuid,text) from public,anon,authenticated;
grant execute on function public.desk_insert_customer_booking(jsonb,uuid,text) to service_role;
