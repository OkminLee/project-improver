이 프로젝트에서 다음 개선 항목을 구현하고, 커밋/PR까지 완료해.

프로젝트: {{PROJECT_NAME}} ({{PROJECT_TYPE}})
경로: {{PROJECT_PATH}}

제목: {{ITEM_TITLE}}
카테고리: {{ITEM_CATEGORY}}
상세: {{ITEM_DESCRIPTION}}
예상효과: {{ITEM_EFFECT}}
담당 에이전트: {{ITEM_AGENT}}
담당 스킬: {{ITEM_SKILL}}
브랜치: {{BRANCH}} (이미 생성됨, 현재 체크아웃 상태)

워크플로우:
{{WORKFLOW_STEPS}}

각 단계의 에이전트를 Task 도구로 호출해. 빌드가 성공해야 다음 단계로 진행.
기존 패턴을 먼저 파악하고 따라.
배포가 실패해도 결과 JSON에 기록하고 계속 진행해.

결과를 아래 JSON으로 {{RESULT_PATH}} 파일에 Write 도구로 저장:
{"pr_url":"PR의 실제 URL","build_number":"빌드 넘버","testflight":"success 또는 failed 또는 skipped","error":"실패시 에러 메시지"}
