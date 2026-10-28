-- 영상 댓글 비활성화 감지 플래그(불러오기 시 statistics.commentCount 부재로 판정).
alter table public.yt_video
  add column if not exists comments_disabled boolean not null default false;

grant all on public.yt_video to service_role;
