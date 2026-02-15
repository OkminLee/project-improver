---
name: approve
description: 승인된 개선 항목을 자동 구현 (브랜치 → 구현 → 커밋 → PR)
user_invocable: true
arguments: "{{ARGUMENTS}}"
metadata:
  requires:
    bins: ["python3", "git"]
---

# /improve:approve

승인된 개선 항목을 자동으로 구현합니다.

## 인자

`{{ARGUMENTS}}`에서 항목 ID를 추출합니다.
- 단일: `/improve:approve 1`
- 복수(쉼표 구분): `/improve:approve 1,3,5`
- 복수(공백 구분): `/improve:approve 1 3 5`

인자가 비어있으면 사용자에게 항목 번호를 물어봅니다.

## 사전 조건

- `.improver/config.json` 존재
- `.improver/proposals/` 아래에 제안서 JSON 존재
- Git 저장소여야 함

## 실행 절차

### 1. 설정 및 제안서 로드

`.improver/config.json`을 Read 도구로 읽어 프로젝트 정보를 추출합니다.

최신 제안서를 찾습니다:
```bash
ls -1t .improver/proposals/*.json 2>/dev/null | head -1
```

제안서 JSON을 Read 도구로 읽고, 요청된 ID의 항목을 추출합니다.

### 2. 각 항목별 처리 루프

요청된 각 ID에 대해 순차적으로 처리합니다:

#### 2a. 항목 정보 확인

제안서에서 해당 ID의 항목을 찾습니다. 없으면 경고 후 다음 항목으로 넘어갑니다.
항목 정보를 사용자에게 보여주고 진행을 확인합니다:
- 제목, 카테고리, 설명, 예상효과, 난이도

#### 2b. Git 브랜치 생성

Bash 도구로 Git 작업을 수행합니다:

```bash
# 현재 상태 확인
git status --porcelain

# 변경사항이 있으면 stash
git stash push -m "improver: before item #<id>"

# base 브랜치로 이동 및 업데이트
git checkout <base_branch>
git pull origin <base_branch> 2>/dev/null || true

# 개선 브랜치 생성
git checkout -b improvement/YYYY-MM-DD-<slug>
```

slug는 제목에서 생성합니다 (영문+숫자+한글, 공백→하이픈, 40자 제한).

#### 2c. 워크플로우 실행

`approve.workflow` 설정에 따라 단계별로 실행합니다.
기본 워크플로우: `plan → test → implement → review → build → commit → pr`

**[plan]** 구현 계획 수립
- 변경할 파일 목록과 접근 방식을 정리
- 필요시 Task 도구로 전문 에이전트 호출

**[test]** 테스트 작성 (TDD)
- 개선 항목에 대한 테스트를 먼저 작성
- 기존 테스트가 깨지지 않는지 확인

**[implement]** 구현
- 계획에 따라 코드 변경
- 기존 패턴과 컨벤션을 따름
- 최소한의 변경으로 목표 달성

**[review]** 셀프 리뷰
- 변경사항이 제안 의도와 일치하는지 확인
- 불필요한 변경이 섞이지 않았는지 확인

**[build]** 빌드 검증
- 프로젝트 타입에 맞는 빌드 명령 실행
  - iOS: `xcodebuild -scheme <scheme> ...`
  - Web: `npm run build`
  - Generic: config의 buildCommand
- 빌드 실패 시 수정 후 재시도 (최대 3회)

**[commit]** 커밋
- 변경된 파일만 staging
- 커밋 메시지: `improve: <제목>` 형식
- `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>` 포함

**[pr]** PR 생성
```bash
gh pr create \
  --title "improve: <제목>" \
  --body "<PR 본문>" \
  --base <base_branch>
```

PR 본문 형식:
```markdown
## Summary
- <개선 항목 설명>
- <변경 사항 요약>

## Proposal
- Category: <카테고리>
- Difficulty: <난이도>
- Expected Effect: <예상효과>

## Test plan
- [ ] 빌드 성공
- [ ] 테스트 통과
- [ ] 기존 기능 영향 없음
```

#### 2d. 결과 저장

`.improver/results/YYYY-MM-DD-<id>.json`에 Write 도구로 결과를 저장합니다:

```json
{
  "id": 1,
  "title": "<제목>",
  "branch": "improvement/YYYY-MM-DD-<slug>",
  "pr_url": "<PR URL>",
  "status": "success | partial | failed",
  "workflow_results": {
    "plan": "done",
    "test": "done",
    "implement": "done",
    "review": "done",
    "build": "success | failed",
    "commit": "done",
    "pr": "<PR URL> | failed"
  },
  "error": ""
}
```

#### 2e. 알림

결과를 사용자에게 보고합니다.
`notify.channel`이 `terminal`이 아닌 경우 Bash 도구로 알림을 전송합니다:
```bash
openclaw message send --channel <channel> --target <target> --message "<메시지>"
```

### 3. base 브랜치 복귀

모든 항목 처리 후 base 브랜치로 돌아갑니다:
```bash
git checkout <base_branch>
```

## 주의사항

- 각 항목은 독립된 브랜치에서 작업합니다
- 빌드 실패 시 최대 3회 수정 시도 후 partial 상태로 기록
- PR 생성 실패는 치명적이지 않음 — 브랜치와 커밋은 유지
- stash한 변경사항은 모든 작업 완료 후 `git stash pop`으로 복원합니다
- 사용자가 중단을 요청하면 현재 항목까지만 완료하고 중지합니다
