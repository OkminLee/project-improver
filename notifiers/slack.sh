#!/bin/bash
# slack.sh — Slack 노티파이어 (openclaw message send 사용)

notifier_send() {
  local message="$1"
  local title="${2:-project-improver}"
  local target
  target=$(config_get "notify.target" 2>/dev/null || echo "")

  if [ -z "$target" ]; then
    log_warn "Slack target이 설정되지 않음 (notify.target)"
    return 1
  fi

  openclaw message send --channel slack --target "$target" \
    --message "[$title] $message" 2>/dev/null || {
    log_warn "Slack 메시지 전송 실패"
    return 1
  }
}

notifier_send_thread() {
  local message="$1"
  local thread_id="$2"
  local title="${3:-project-improver}"
  local target
  target=$(config_get "notify.target" 2>/dev/null || echo "")

  if [ -z "$target" ]; then
    log_warn "Slack target이 설정되지 않음"
    return 1
  fi

  if [ -n "$thread_id" ] && [ "$thread_id" != "none" ]; then
    openclaw message send --channel slack --target "$target" \
      --reply-to "$thread_id" --message "[$title] $message" 2>/dev/null || return 1
  else
    notifier_send "$message" "$title"
  fi
}
