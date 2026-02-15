---
name: analyze
description: 프로젝트 분석 → 개선 제안서 생성
user_invocable: true
arguments: "{{ARGUMENTS}}"
metadata:
  requires:
    bins: ["python3", "git"]
---

# /improve:analyze

프로젝트를 분석하고 개선 제안서를 `.improver/proposals/YYYY-MM-DD.json`에 생성합니다.

## 사전 조건

`.improver/config.json`이 존재해야 합니다. 없으면 `/improve:init`을 먼저 실행하라고 안내합니다.

## 실행 절차

### 1. 설정 로드

`.improver/config.json`을 Read 도구로 읽고 다음 정보를 추출합니다:
- `project.name`, `project.type`, `project.path`
- `analyze.maxItems` (기본: 5)
- `analyze.categories`
- `analyze.agents` (사용 가능한 에이전트 목록)

### 2. iOS 프로젝트 — 빌드 및 UI 분석 (선택적)

`project.type`이 `ios`이고 macOS 환경(`uname == Darwin`)인 경우에만 수행합니다.

빌드가 필요하면 Bash 도구로 실행합니다:
```bash
# Simulator 부팅 확인
xcrun simctl list devices booted -j

# xcodebuild
xcodebuild -project <xcodeproj경로> \
  -scheme <scheme> \
  -destination "platform=iOS Simulator,name=<simulator>" \
  -derivedDataPath .build build

# 앱 설치 및 실행
xcrun simctl install booted <app경로>
xcrun simctl launch booted <bundleId> [-ScreenshotMode true]
```

UI 분석이 가능하면 (`peekaboo` 명령 존재 시) Bash 도구로 Peekaboo를 호출합니다:
```bash
peekaboo see --app "Simulator" --json
```

빌드나 UI 분석이 실패해도 코드 기반 분석으로 계속 진행합니다.

### 3. 코드베이스 분석

다음을 수행합니다:

1. **프로젝트 구조 파악**: Glob 도구로 주요 파일 패턴 검색
2. **소스코드 읽기**: Read 도구로 핵심 파일 읽기
3. **아키텍처 분석**: 패턴, 의존성, 계층 구조 파악
4. **개선점 도출**: 아래 카테고리별로 구체적 개선점 식별

카테고리: `analyze.categories` 설정값 사용 (기본: UI·UX, 기능, 성능, 테스트, 아키텍처)

### 4. 에이전트 활용 (선택적)

`analyze.agents`에 에이전트가 설정되어 있으면 Task 도구로 전문 분석 에이전트를 호출합니다.
설정되어 있지 않으면 직접 분석합니다.

에이전트 예시:
- `ios-architect`: 아키텍처 분석
- `swift-code-reviewer`: 코드 품질 리뷰
- `ios-planner`: 구현 계획 수립

### 5. 제안서 JSON 생성

분석 결과를 `.improver/proposals/YYYY-MM-DD.json`에 Write 도구로 저장합니다.

오늘 날짜를 Bash 도구로 가져옵니다:
```bash
date +%Y-%m-%d
```

JSON 형식:
```json
{
  "date": "YYYY-MM-DD",
  "project": {
    "name": "<프로젝트명>",
    "type": "<타입>"
  },
  "items": [
    {
      "id": 1,
      "category": "UI·UX | 기능 | 성능 | 테스트 | 아키텍처",
      "title": "제안 제목",
      "description": "구체적 개선안 2-3문장 (파일:라인 참조 포함)",
      "expectedEffect": "예상 효과 1문장",
      "difficulty": "상 | 중 | 하",
      "agent": "담당 에이전트명",
      "skill": "담당 스킬명"
    }
  ]
}
```

### 6. 결과 보고

생성된 제안서를 사용자에게 보여줍니다:
- 항목 수
- 각 항목의 ID, 카테고리, 제목, 난이도
- 다음 단계 안내: `/improve:approve <id>` 실행

## 분석 기준

각 항목은 반드시 다음을 포함해야 합니다:
- **구체적 파일:라인 참조** — "어딘가에 문제" 같은 모호한 표현 금지
- **실행 가능한 제안** — 바로 구현할 수 있는 수준의 구체성
- **예상 효과** — 정량적이거나 명확한 정성적 효과
- **적절한 난이도 판정** — 변경 범위와 리스크 기반

`maxItems` 이하로 우선순위가 높은 항목만 선정합니다.

## 주의사항

- 이미 같은 날짜의 제안서가 있으면 덮어쓸지 사용자에게 확인합니다
- 빌드 실패, UI 분석 불가 등은 치명적 오류가 아닙니다 — 코드 기반 분석으로 진행
- JSON 출력은 반드시 유효한 JSON이어야 합니다
