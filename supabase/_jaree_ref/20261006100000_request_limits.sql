begin;
create table if not exists public.desk_request_limits(bucket text primary key,window_start timestamptz not null,hits integer not null);
alter table public.desk_request_limits enable row level security;
revoke all on public.desk_request_limits from anon,authenticated;
grant select,insert,update,delete on public.desk_request_limits to service_role;
create or replace function public.desk_take_request(bucket_key text,max_hits integer,window_seconds integer) returns boolean language plpgsql security invoker set search_path='' as $$
declare n integer; begin
 if length(bucket_key)>200 or max_hits<1 or window_seconds<1 then raise exception '잘못된 요청 제한'; end if;
 insert into public.desk_request_limits(bucket,window_start,hits) values(bucket_key,now(),1) on conflict(bucket) do update set window_start=case when desk_request_limits.window_start<now()-make_interval(secs=>window_seconds) then now() else desk_request_limits.window_start end,hits=case when desk_request_limits.window_start<now()-make_interval(secs=>window_seconds) then 1 else least(desk_request_limits.hits+1,max_hits+1) end returning hits into n;
 delete from public.desk_request_limits where window_start<now()-interval '1 day';
 return n<=max_hits;
end $$;
revoke all on function public.desk_take_request(text,integer,integer) from public,anon,authenticated;
grant execute on function public.desk_take_request(text,integer,integer) to service_role;
commit;
