-- 영상 "내용 추출"(LLM 분석) 저장. 추출=수집, 게시=나중에 분리.
alter table public.yt_video add column if not exists analysis   jsonb;        -- { summary, worry_oneline, comment, source, provider, model }
alter table public.yt_video add column if not exists extracted_at timestamptz; -- 추출 완료 시각(있으면 "댓글 달기" 리스트에 노출)
create index if not exists yt_video_extracted_idx on public.yt_video (extracted_at desc nulls last);
grant all on public.yt_video to service_role;
