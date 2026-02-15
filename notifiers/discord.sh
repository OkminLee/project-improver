#!/bin/bash
# discord.sh — Discord 노티파이어 (openclaw message send 사용)

notifier_send() {
  local message="$1"
  local title="${2:-project-improver}"
  local target
  target=$(config_get "notify.target" 2>/dev/null || echo "")

  if [ -z "$target" ]; then
    log_warn "Discord target이 설정되지 않음 (notify.target)"
    return 1
  fi

  openclaw message send --channel discord --target "$target" \
    --message "**[$title]** $message" 2>/dev/null || {
    log_warn "Discord 메시지 전송 실패"
    return 1
  }
}

notifier_send_thread() {
  local message="$1"
  local thread_id="$2"
  local title="${3:-project-improver}"
  # Discord는 스레드 답글 미지원 — 일반 메시지로 전송
  notifier_send "$message" "$title"
}
