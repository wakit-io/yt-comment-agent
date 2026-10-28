-- 공개 이미지 버킷(메인 이미지·포트폴리오 등). 공개 버킷은 /storage/v1/object/public/ 로 RLS 없이 읽힘.
insert into storage.buckets (id, name, public) values ('fl-public', 'fl-public', true)
  on conflict (id) do update set public = true;
