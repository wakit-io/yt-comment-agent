// 샘플 데이터 시드 — 키 없이 화면 확인용. 실행: node scripts/seed-sample.mjs
//   영상(추출본) + 댓글 기록(게시/실패)을 넣어 대시보드·리스트·상세가 채워지게.
import { supa } from '../lib/supa.mjs';

const now = Date.now();
const iso = (minsAgo) => new Date(now - minsAgo * 60000).toISOString();

const videos = [
  { id: 'sample_aaa111', title: '남자친구 연락이 점점 뜸해져요… 이거 끝인가요?', channel_title: '연애상담소 러브톡', view_count: 42310, published_at: iso(60 * 24 * 2), thumb: 'https://i.ytimg.com/vi/aaa/mqdefault.jpg',
    analysis: { source: 'video', worry_oneline: '사귄 지 1년, 남친 연락 빈도가 줄어 불안한 상황', summary: '1년 된 커플의 연락 빈도 감소 고민. 영상 속 사연자는 "예전엔 1시간마다 오던 카톡이 이젠 하루 한두 번"이라며 권태기인지 마음이 식은 건지 혼란스러워함. 상담사는 연락 횟수보다 질을 보라고 조언.', comment: '저도 딱 그 "하루 한두 번" 구간 지나봐서 남 일 같지 않네요. 3분쯤에 하신 말이 제 얘기 같아서… 이게 권태기인지 진짜 식은 건지 혼자선 답이 안 나오더라고요. 이런 거 사주로 보면 흐름이 보인다던데 괜히 궁금해지네요.' } },
  { id: 'sample_bbb222', title: '짝사랑 6개월차, 고백 타이밍 언제가 좋을까요?', channel_title: '모태솔로 탈출기', view_count: 18750, published_at: iso(60 * 24 * 5), thumb: 'https://i.ytimg.com/vi/bbb/mqdefault.jpg',
    analysis: { source: 'video', worry_oneline: '같은 동아리 짝사랑, 친구로 지낸 6개월 뒤 고백 고민', summary: '동아리에서 만난 상대를 6개월째 짝사랑 중인 사연. 친구 관계가 편해서 고백하면 어색해질까 두렵지만, 상대에게 다른 사람이 생길까 조급함도 큼. 영상은 "지금이 아니면 평생 친구"라는 포인트를 강조.', comment: '"지금이 아니면 평생 친구" 이 말에 가슴이 쿵 했어요. 저도 6개월째 친구인 척 중인데… 타이밍이라는 게 진짜 어렵네요. 이런 건 운이나 인연의 때가 있는 건지 사주라도 한번 보고 싶어지는 밤입니다.' } },
  { id: 'sample_ccc333', title: '환승이별 당했어요… 어떻게 극복하죠?', channel_title: '이별후회노트', view_count: 65200, published_at: iso(60 * 24 * 1), thumb: 'https://i.ytimg.com/vi/ccc/mqdefault.jpg',
    analysis: { source: 'metadata', worry_oneline: '2년 연애 후 환승이별, 자존감 회복 고민', summary: '2년 사귄 연인에게 환승이별을 당한 사연자의 극복기. 상대가 이미 다른 사람과 시작한 걸 알게 되어 배신감과 자책이 크고, 다시 연애할 수 있을지 두려움을 토로.', comment: '환승이별이 제일 아픈 것 같아요. 내 잘못인가 계속 곱씹게 되고… 영상 보면서 많이 울었네요. 이런 상처도 결국 지나간다는데, 다음 인연은 언제쯤 올지 흐름이라도 알면 버티기 쉬울 텐데요.' } },
  { id: 'sample_ddd444', title: '소개팅 3번 연속 애프터 없음, 제가 문제일까요?', channel_title: '연애코치 김작가', view_count: 29400, published_at: iso(60 * 24 * 7), thumb: 'https://i.ytimg.com/vi/ddd/mqdefault.jpg',
    analysis: { source: 'video', worry_oneline: '소개팅 연속 실패로 자신감 하락', summary: '최근 소개팅 3번이 모두 애프터로 이어지지 못한 사연. 대화는 잘 통했다고 느꼈는데 결과가 없어 자기 매력에 의문을 가짐. 코치는 첫 만남의 "여운 남기기" 전략을 설명.', comment: '대화 잘 통했다고 생각했는데 애프터가 없을 때 진짜 멘붕이죠. "여운 남기기" 부분 메모했어요. 근데 저는 매번 왜 이런 패턴인지… 타고난 연애운 같은 게 있나 싶어서 한번 제대로 봐보고 싶네요.' } },
];

const logs = [
  { video_id: 'sample_aaa111', video_title: videos[0].title, profile: '유튜브1', body: videos[0].analysis.comment, status: 'posted', success: true, comment_id: 'Ug_sample1', created_at: iso(30 ), featured: true },
  { video_id: 'sample_bbb222', video_title: videos[1].title, profile: '유튜브1', body: videos[1].analysis.comment, status: 'posted', success: true, comment_id: 'Ug_sample2', created_at: iso(95), featured: true },
  { video_id: 'sample_ccc333', video_title: videos[2].title, profile: '유튜브2', body: videos[2].analysis.comment, status: 'posted', success: true, comment_id: 'Ug_sample3', created_at: iso(60 * 20), featured: false },
  { video_id: 'sample_ddd444', video_title: videos[3].title, profile: '유튜브1', body: videos[3].analysis.comment, status: 'failed', success: false, error: '게시 실패: 댓글이 사용 중지된 영상입니다.', created_at: iso(60 * 26), featured: false },
];

async function main() {
  const vrows = videos.map((v) => ({ ...v, extracted_at: iso(Math.floor(Math.random() * 1000)) }));
  const { error: ve } = await supa.from('yt_video').upsert(vrows, { onConflict: 'id' });
  if (ve) throw ve;
  for (const l of logs) l.video_link = 'https://www.youtube.com/watch?v=' + l.video_id;
  for (const l of logs) if (l.success) l.comment_link = l.video_link + '&lc=' + l.comment_id;
  // 기존 샘플 로그 정리 후 삽입(중복 방지)
  await supa.from('yt_log').delete().in('video_id', videos.map((v) => v.id));
  const { error: le } = await supa.from('yt_log').insert(logs);
  if (le) throw le;
  console.log(`시드 완료: 영상 ${vrows.length}건, 댓글기록 ${logs.length}건(성공 ${logs.filter((l) => l.success).length}·실패 ${logs.filter((l) => !l.success).length})`);
  process.exit(0);
}
main().catch((e) => { console.error('시드 실패:', e.message || e); process.exit(1); });
