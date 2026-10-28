-- 브랜드 공개 모드: 켜면 댓글을 브랜드 공식 계정 입장에서(신분 공개) 작성.
-- 끄면(기본) 일반 시청자 페르소나로 브랜드명 없이 주제 궁금증만 남김.
alter table public.yt_setting
  add column if not exists brand_open boolean not null default false;

grant all on public.yt_setting to service_role;
