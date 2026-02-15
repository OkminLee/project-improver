---
name: improve-approve
description: 승인된 개선 항목을 자동 구현 (improve CLI로 Ghostty+tmux에서 Claude Code 실행)
metadata:
  {
    "openclaw": {
      "emoji": "✅",
      "os": ["darwin"],
      "requires": {
        "bins": ["improve", "claude", "python3", "git"]
      }
    }
  }
---

# improve-approve — 개선 항목 승인 및 자동 구현

승인된 개선 항목을 Ghostty 터미널에서 Claude Code로 자동 구현합니다.

## 트리거 패턴

다음과 같은 메시지를 받으면 이 스킬을 실행합니다:
- "1번 승인", "1, 3번 승인", "2,4,5번 승인"
- "approve 1", "approve 1,3,5"
- 숫자 + "승인" 키워드 조합

## 실행 방법

### 1. 항목 ID 추출

메시지에서 숫자를 추출합니다.
예: "1, 3번 승인" → `1 3`
예: "approve 2,4" → `2 4`

### 2. 프로젝트 경로 결정

메시지에 경로가 있으면 사용합니다. 없으면:
- 최근 `improve analyze`를 실행한 프로젝트를 추정합니다
- 그래도 모르겠으면 사용자에게 물어봅니다

`.improver/config.json`과 `.improver/proposals/*.json`이 존재하는지 확인합니다.

### 3. 백그라운드로 improve approve 실행

```bash
nohup bash -c 'cd <project_path> && improve approve <ids> --notify <channel>' >> ~/.openclaw/logs/improve-approve.log 2>&1 &
```

`<ids>`는 쉼표 구분: `1,3,5`
`<channel>`은 메시지가 온 채널에 맞춰 설정합니다.

### 4. 응답

"#1, #3 항목 구현 스크립트를 실행했습니다. 항목당 수십분 소요됩니다." 라고만 응답합니다.

**주의:**
- `improve approve`는 항목마다 Ghostty 터미널을 열고 Claude Code를 실행합니다
- 항목당 30분 이상 소요될 수 있습니다
- 절대 결과를 기다리지 마세요. 백그라운드로 실행하고 즉시 응답합니다
- 결과 알림은 `improve` CLI의 notifier가 처리합니다
- 에이전트가 직접 message 도구로 알림을 보내지 마세요
- PR 생성, 커밋 등도 모두 Claude Code가 처리합니다
