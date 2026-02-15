---
name: init
description: 프로젝트 초기화 — .improver/ 디렉토리와 config.json 생성
user_invocable: true
arguments: "{{ARGUMENTS}}"
---

# /improve:init

프로젝트 디렉토리에 `.improver/` 설정을 초기화합니다.

## 인자 파싱

`{{ARGUMENTS}}`에서 옵션을 추출합니다:
- `--type <TYPE>`: 프로젝트 타입 (ios, web, generic). 생략 시 자동 감지
- `--path <PATH>`: 프로젝트 경로. 생략 시 현재 작업 디렉토리
- `--name <NAME>`: 프로젝트 이름. 생략 시 디렉토리명

인자가 비어있으면 현재 디렉토리를 대상으로 자동 감지합니다.

## 실행 절차

### 1. 프로젝트 경로 결정

`--path`가 지정되지 않으면 현재 작업 디렉토리를 사용합니다.
경로가 존재하는지 확인합니다.

### 2. 프로젝트 타입 자동 감지

`--type`이 생략된 경우 아래 규칙으로 감지합니다:
- `*.xcodeproj` 파일이 존재 → `ios`
- `package.json` 파일이 존재 → `web`
- `build.gradle` 또는 `build.gradle.kts` 존재 → `android`
- 그 외 → `generic`

Glob 도구로 패턴을 검색하여 판별합니다.

### 3. 디렉토리 생성

Bash 도구로 다음 디렉토리를 생성합니다:
```bash
mkdir -p .improver/proposals .improver/results .improver/logs
```

### 4. config.json 생성

`.improver/config.json`이 이미 존재하면 덮어쓰지 않고 경고만 출력합니다.

존재하지 않으면, 감지된 타입에 따라 config.json을 Write 도구로 생성합니다.

Git 저장소인 경우 현재 브랜치를 기본 브랜치로 설정합니다:
```bash
git symbolic-ref --short HEAD 2>/dev/null || echo "main"
```

#### iOS 타입 config.json 예시:
```json
{
  "project": {
    "name": "<프로젝트명>",
    "type": "ios",
    "path": "<절대경로>",
    "branch": "<현재브랜치>"
  },
  "ios": {
    "scheme": "<xcodeproj에서 추출>",
    "bundleId": "",
    "simulator": "iPhone 17 Pro",
    "screenshotMode": false,
    "deployCommand": ""
  },
  "analyze": {
    "agents": ["ios-architect", "swift-code-reviewer", "ios-planner"],
    "maxItems": 5,
    "categories": ["UI·UX", "기능", "성능", "테스트", "아키텍처"]
  },
  "approve": {
    "workflow": ["plan", "test", "implement", "review", "build", "commit", "pr"],
    "prBase": "<현재브랜치>"
  },
  "notify": {
    "channel": "terminal"
  }
}
```

#### Web 타입: `"web": { "buildCommand": "npm run build", ... }` 섹션 포함
#### Generic 타입: `"generic": { "buildCommand": "", ... }` 섹션 포함

### 5. 완료 메시지

초기화 결과를 사용자에게 보고합니다:
- 프로젝트 이름, 타입, 경로
- 생성된 디렉토리 목록
- 다음 단계 안내: `/improve:analyze` 실행

## 주의사항

- `.improver/config.json`이 이미 존재하면 절대 덮어쓰지 않습니다
- `.improver/proposals/`, `.improver/results/`, `.improver/logs/`는 `.gitignore`에 추가를 권장합니다
- config.json의 경로는 반드시 절대 경로를 사용합니다
