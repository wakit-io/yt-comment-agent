-- 커뮤니티 메모에 이미지 1장(선택). desk-assets 버킷 community/ 프리픽스에 업로드된 공개 URL.
begin;
alter table public.desk_memos add column if not exists image_url text not null default '';
commit;
