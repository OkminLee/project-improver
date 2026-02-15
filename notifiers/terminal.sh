#!/bin/bash
# terminal.sh — 터미널 출력 노티파이어 (기본)

notifier_send() {
  local message="$1"
  local title="${2:-project-improver}"
  echo -e "\033[1;36m[$title]\033[0m $message"
}

notifier_send_thread() {
  local message="$1"
  local thread_id="$2"
  local title="${3:-project-improver}"
  echo -e "\033[1;36m[$title]\033[0m (thread: $thread_id) $message"
}
