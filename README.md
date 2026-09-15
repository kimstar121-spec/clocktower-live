# Clocktower Live

모바일 우선 실시간 시계탑 진행 보조 앱입니다. 스토리텔러가 방을 만들고 최대 10명이 코드로 참가해 역할 확인, 낮/밤 전환, 밤 행동 제출과 취합을 사용할 수 있습니다.

## 실행

`.env.example`을 `.env.local`로 복사해 Supabase URL과 publishable key를 설정한 뒤 `npm install && npm run dev`를 실행합니다. Supabase SQL Editor에서 `supabase/schema.sql`을 적용하고 Anonymous Sign-Ins를 활성화해야 합니다.
