-- 댓글 페르소나(아웃리치 댓글의 목소리/톤). 과제 "영상을 본 시청자의 페르소나로 작성" 대응.
-- ⚠️ 가짜 신원 다계정이 아니라, 내가 다는 댓글이 어떤 톤/목소리일지 정의하는 설정.
alter table public.yt_setting
  add column if not exists persona text not null default
  '연애에 지친 20~30대 시청자. 공감 잘하고 솔직한 구어체(반말 섞어 편하게). 자기 연애도 잘 안 풀려서 ''운명''이나 사주/인연에 은근히 관심이 생긴 사람의 말투.';

grant all on public.yt_setting to service_role;
