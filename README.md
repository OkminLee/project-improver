# project-improver

프로젝트 분석 → 개선 제안 → 승인 → 자동 구현까지의 워크플로우를 자동화하는 CLI 도구.

Claude Code를 활용해 프로젝트를 분석하고, 승인된 개선 항목을 자동으로 구현합니다.

## 설치

```bash
git clone <repo-url> ~/Work/project-improver

# PATH에 추가 (선택)
echo 'export PATH="$HOME/Work/project-improver/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 요구사항

- macOS (Peekaboo, osascript 사용)
- Python 3
- [Claude Code](https://claude.ai/code) CLI (`claude` 명령)
- Git
- Ghostty 터미널 (또는 `TERMINAL_APP` 환경변수로 변경)

iOS 프로젝트 추가 요구:
- Xcode + xcodebuild
- iOS Simulator
- [Peekaboo](https://github.com/steipete/Peekaboo) (UI 시각 분석용, 선택적)

## 빠른 시작

```bash
# 1. 프로젝트 초기화
cd ~/Work/my-project
improve init

# 2. 분석 실행 (Claude Code가 프로젝트를 분석하고 개선안 생성)
improve analyze

# 3. 제안 목록 확인
improve list

# 4. 승인 및 자동 구현
improve approve 1,3
```

## 명령어

### `improve init`

프로젝트 디렉토리에 `.improver/` 설정을 생성합니다.

```bash
improve init                    # 자동 감지 (ios/web/generic)
improve init --type ios         # 타입 지정
improve init --path ~/Work/app  # 경로 지정
improve init --name my-app      # 이름 지정
```

자동 감지 규칙:
- `*.xcodeproj` 존재 → `ios`
- `package.json` 존재 → `web`
- 기타 → `generic`

### `improve analyze`

프로젝트를 분석하고 개선 제안을 생성합니다.

```bash
improve analyze                  # 터미널 출력
improve analyze --notify slack   # Slack으로 결과 전송
improve analyze --headless       # 비대화형 모드 (CI용)
```

워크플로우:
1. 플러그인으로 빌드 + UI 분석 (iOS: xcodebuild + Peekaboo)
2. Claude Code가 소스코드 + UI 분석 결과 기반으로 개선점 도출
3. 결과를 `.improver/proposals/YYYY-MM-DD.json`에 저장

### `improve list`

최신 제안 목록을 표시합니다.

```bash
improve list
```

출력 예시:
```
최신 제안서: 2026-02-15.json

  #1. [성능] coverImageData 외부 저장소 적용
     Book 모델의 coverImageData를 외부 파일로 분리 (Book.swift:45)
     예상효과: 메모리 사용량 30% 감소
     난이도: 중 | agent: ios-architect | skill: plan
```

### `improve approve`

승인된 항목을 자동으로 구현합니다.

```bash
improve approve 1               # 1번 항목 구현
improve approve 1,3,5            # 여러 항목 구현
improve approve 2 --notify slack # Slack으로 진행상황 전송
```

항목별 워크플로우 (설정에서 커스텀 가능):
1. Git 브랜치 생성 (`improvement/YYYY-MM-DD-slug`)
2. Claude Code가 계획 → 테스트 → 구현 → 리뷰 → 빌드 → 커밋 → PR 생성

### `improve status`

현재 상태를 표시합니다.

```bash
improve status
```

## 설정

`.improver/config.json` 파일로 프로젝트별 설정을 관리합니다.

```json
{
  "project": {
    "name": "my-app",
    "type": "ios",
    "path": "/Users/me/Work/my-app",
    "branch": "develop"
  },
  "ios": {
    "scheme": "my-app",
    "bundleId": "com.example.myapp",
    "simulator": "iPhone 17 Pro",
    "screenshotMode": true,
    "deployCommand": "bundle exec fastlane beta"
  },
  "analyze": {
    "agents": ["ios-architect", "swift-code-reviewer"],
    "maxItems": 5,
    "categories": ["UI·UX", "기능", "성능", "테스트", "아키텍처"]
  },
  "approve": {
    "workflow": ["plan", "test", "implement", "review", "build", "commit", "pr"],
    "prBase": "develop"
  },
  "notify": {
    "channel": "slack",
    "target": "channel:app-reading"
  }
}
```

## 플러그인

프로젝트 타입별 빌드/분석/배포 로직은 플러그인으로 분리되어 있습니다.

### 기본 제공 플러그인

| 플러그인 | 빌드 | UI 분석 | 배포 |
|---------|------|---------|------|
| `ios` | xcodebuild + Simulator | Peekaboo | config 명령 |
| `web` | npm run build | (수동) | config 명령 |
| `generic` | config 명령 | (없음) | config 명령 |

### 커스텀 플러그인 작성

`plugins/<name>/plugin.sh` 파일을 생성하고 다음 함수를 구현하세요:

```bash
#!/bin/bash
# plugins/my-type/plugin.sh

plugin_detect() {
    local project_path="${1:-.}"
    # 이 프로젝트가 해당 타입인지 판별
    # return 0 = yes, return 1 = no
    [[ -f "$project_path/my-config-file" ]]
}

plugin_build() {
    local config_file="$1"
    # 빌드 실행 (선택적)
    local cmd=$(json_get "$config_file" "my-type.buildCommand" 2>/dev/null)
    [[ -n "$cmd" ]] && eval "$cmd"
}

plugin_ui_analysis() {
    local config_file="$1"
    # UI 분석 결과를 stdout에 출력
    echo "UI 분석 결과..."
}

plugin_deploy() {
    local config_file="$1"
    # 배포 실행 (선택적)
    local cmd=$(json_get "$config_file" "my-type.deployCommand" 2>/dev/null)
    [[ -n "$cmd" ]] && eval "$cmd"
}
```

## 알림 채널

| 채널 | 설명 | 요구사항 |
|------|------|---------|
| `terminal` | 터미널 컬러 출력 (기본) | 없음 |
| `slack` | Slack 채널 전송 | OpenClaw (`openclaw message send`) |
| `discord` | Discord 채널 전송 | OpenClaw (`openclaw message send`) |

```bash
# Slack으로 분석 결과 전송
improve analyze --notify slack

# config.json에서 기본 채널 설정
# "notify": { "channel": "slack", "target": "channel:my-channel" }
```

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `IMPROVE_HEADLESS` | 0 | 1이면 비대화형 모드 |
| `TERMINAL_APP` | Ghostty | 터미널 앱 이름 |
| `DEBUG` | 0 | 1이면 디버그 로깅 |

## 프로젝트 구조

```
project-improver/
├── bin/improve              # CLI 엔트리포인트
├── lib/
│   ├── core.sh              # 공용 함수 (로깅, JSON, 템플릿)
│   ├── config.sh            # 설정 로드/검증
│   ├── analyze.sh           # 분석 엔진
│   ├── approve.sh           # 구현 엔진
│   └── claude-runner.sh     # Claude Code 실행기
├── plugins/
│   ├── ios/                 # iOS 플러그인
│   │   ├── plugin.sh
│   │   └── visual-helpers.sh
│   ├── web/plugin.sh        # Web 플러그인
│   └── generic/plugin.sh    # Generic 플러그인 (폴백)
├── templates/
│   ├── config.json          # 기본 설정 템플릿
│   ├── analyze-prompt.md    # 분석 프롬프트
│   └── approve-prompt.md    # 구현 프롬프트
├── notifiers/
│   ├── terminal.sh          # 터미널 알림
│   ├── slack.sh             # Slack 알림
│   └── discord.sh           # Discord 알림
└── README.md
```

## 기존 reading 스크립트에서 마이그레이션

```bash
# 기존
~/.openclaw/scripts/reading-improvement.sh
~/.openclaw/scripts/reading-approve.sh <thread_ts> <item_ids>

# 새로운 방식
cd ~/Work/reading
improve init --type ios
improve analyze --notify slack
improve approve 1,3 --notify slack
```

## 라이선스

MIT
