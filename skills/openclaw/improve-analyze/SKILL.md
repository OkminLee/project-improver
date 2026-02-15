---
name: improve-analyze
description: 프로젝트 분석 → 개선 제안서 생성 (improve CLI로 Ghostty+tmux에서 Claude Code 실행)
metadata:
  {
    "openclaw": {
      "emoji": "🔍",
      "os": ["darwin"],
      "requires": {
        "bins": ["improve", "claude", "python3", "git"]
      }
    }
  }
---

# improve-analyze — 프로젝트 개선 분석

프로젝트를 분석하고 개선 제안서를 생성합니다. Ghostty 터미널에서 Claude Code를 실행하는 방식입니다.

## 트리거 패턴

다음과 같은 메시지를 받으면 이 스킬을 실행합니다:
- "분석해줘", "analyze", "개선 분석"
- "~/Work/reading 분석해줘" (경로 지정)
- "프로젝트 분석 실행해줘"

## 실행 방법

### 1. 프로젝트 경로 결정

메시지에서 프로젝트 경로를 추출합니다. 경로가 없으면 사용자에게 물어봅니다.
`.improver/config.json`이 존재하는지 확인합니다. 없으면 먼저 `improve init`을 안내합니다.

### 2. 백그라운드로 improve analyze 실행

```bash
nohup bash -c 'improve analyze --notify <channel>' >> ~/.openclaw/logs/improve-analyze.log 2>&1 &
```

`<channel>`은 메시지가 온 채널에 맞춰 설정합니다:
- Slack → `--notify slack`
- Discord → `--notify discord`
- 그 외 → `--notify terminal`

### 3. 응답

"분석 스크립트를 실행했습니다. 완료되면 알림이 갑니다." 라고만 응답합니다.

**주의:**
- `improve analyze`는 Ghostty 터미널을 열고 Claude Code를 실행합니다 (수십분 소요)
- 절대 결과를 기다리지 마세요. 백그라운드로 실행하고 즉시 응답합니다
- 결과 알림은 `improve` CLI의 notifier가 처리합니다
- 에이전트가 직접 message 도구로 알림을 보내지 마세요

### 4. 프로젝트 경로에서 실행

`improve analyze`는 프로젝트 디렉토리에서 실행해야 합니다:
```bash
nohup bash -c 'cd <project_path> && improve analyze --notify slack' >> ~/.openclaw/logs/improve-analyze.log 2>&1 &
```
