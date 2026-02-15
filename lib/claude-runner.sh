#!/bin/bash
# claude-runner.sh — Claude Code 실행 헬퍼 (범용)

# Claude Code 가시적 실행 (Ghostty + tmux 하이브리드)
# 인자: prompt_file, working_dir, done_marker, timeout(기본 600)
claude_run_visible() {
    local prompt_file="$1"
    local working_dir="$2"
    local done_marker="$3"
    local timeout="${4:-600}"

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi

    if [[ ! -d "$working_dir" ]]; then
        log_error "Working directory not found: $working_dir"
        return 1
    fi

    rm -f "$done_marker"

    local socket="/tmp/improver-claude-tmux-$$.sock"
    local session="improver-claude-$$"

    # 프롬프트 파일에 done_marker 지시 추가
    local augmented_prompt="/tmp/claude-augmented-prompt-$$.md"
    {
        cat "$prompt_file"
        echo ""
        echo "작업이 모두 완료되면 반드시 Bash 도구로 다음 명령을 실행해: touch '$done_marker'"
    } > "$augmented_prompt"

    # Ghostty 런처: tmux 세션 생성 + claude 실행 + attach
    local launcher="/tmp/improver-claude-launcher-$$.sh"
    cat > "$launcher" << LAUNCHER_EOF
#!/bin/bash
cd '$working_dir'
tmux -S '$socket' kill-session -t '$session' 2>/dev/null || true
tmux -S '$socket' new-session -d -s '$session' -x 200 -y 50
tmux -S '$socket' send-keys -t '$session' "claude --dangerously-skip-permissions" Enter
exec tmux -S '$socket' attach -t '$session'
LAUNCHER_EOF
    chmod +x "$launcher"

    log_info "새 ${TERMINAL_APP:-Ghostty} 인스턴스 + tmux 실행..."
    open -na "${TERMINAL_APP:-Ghostty}.app" --args --command="bash $launcher"
    sleep 5

    log_info "Claude Code 인터랙티브 시작 (working_dir: $working_dir)"

    # 확인 프롬프트 대기 + 수락 (tmux send-keys)
    log_debug "확인 프롬프트 대기 (12s)..."
    sleep 12

    local pane_output
    pane_output=$(tmux -S "$socket" capture-pane -t "$session" -p 2>/dev/null || echo "")
    if echo "$pane_output" | grep -qiE "bypass|skip|permissions|acknowledge|understand|Yes|dangerous"; then
        log_debug "확인 프롬프트 감지됨"
    fi

    tmux -S "$socket" send-keys -t "$session" Down 2>/dev/null || true
    sleep 0.5
    tmux -S "$socket" send-keys -t "$session" Enter 2>/dev/null || true
    log_debug "확인 수락 전송"

    # Claude Code 준비 대기
    log_debug "Claude Code 시작 대기 (10s)..."
    sleep 10

    # 프롬프트 전송 (tmux send-keys)
    local send_text="$augmented_prompt 파일을 Read 도구로 읽고, 그 안의 모든 지시사항을 빠짐없이 따라 실행해."
    tmux -S "$socket" send-keys -t "$session" "$send_text" 2>/dev/null || true
    sleep 1
    tmux -S "$socket" send-keys -t "$session" Enter 2>/dev/null || true
    sleep 3
    # 멀티라인 입력으로 인식될 경우 대비 추가 Enter
    tmux -S "$socket" send-keys -t "$session" Enter 2>/dev/null || true
    log_info "프롬프트 전송 완료 (파일: $augmented_prompt)"

    # 완료 대기 (done_marker 폴링)
    local elapsed=0
    while [[ ! -f "$done_marker" ]] && [[ $elapsed -lt $timeout ]]; do
        sleep 10
        elapsed=$((elapsed + 10))
        if [[ $((elapsed % 120)) -eq 0 ]]; then
            notify "Claude Code" "진행 중... (${elapsed}s / ${timeout}s)"
        fi
    done

    # 정리
    rm -f "$augmented_prompt" "$launcher"

    tmux -S "$socket" send-keys -t "$session" "/exit" Enter 2>/dev/null || true
    sleep 3
    tmux -S "$socket" send-keys -t "$session" "exit" Enter 2>/dev/null || true
    sleep 2
    tmux -S "$socket" kill-session -t "$session" 2>/dev/null || true
    rm -f "$socket"

    sleep 1

    if [[ -f "$done_marker" ]]; then
        log_info "Claude Code 완료 (${elapsed}s)"
        return 0
    else
        log_error "Claude Code 타임아웃 (${timeout}s)"
        return 1
    fi
}

# Claude Code headless 실행 (비대화형)
# 인자: prompt_file, working_dir, output_file, timeout(기본 600)
claude_run_headless() {
    local prompt_file="$1"
    local working_dir="$2"
    local output_file="$3"
    local timeout="${4:-600}"

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi

    if [[ ! -d "$working_dir" ]]; then
        log_error "Working directory not found: $working_dir"
        return 1
    fi

    log_info "Claude Code headless 실행 (working_dir: $working_dir)"

    local temp_output="/tmp/claude-headless-output-$$.json"

    # claude -p --output-format json < prompt_file 실행 (타임아웃 관리)
    cd "$working_dir" || return 1

    timeout "$timeout" claude -p --output-format json < "$prompt_file" > "$temp_output" 2>&1 &
    local claude_pid=$!

    wait "$claude_pid"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if [[ -f "$temp_output" ]]; then
            mv "$temp_output" "$output_file"
            log_info "Claude Code headless 완료 (output: $output_file)"
            return 0
        else
            log_error "Claude Code headless 실행됐으나 출력 파일 없음"
            return 1
        fi
    elif [[ $exit_code -eq 124 ]]; then
        log_error "Claude Code headless 타임아웃 (${timeout}s)"
        rm -f "$temp_output"
        return 1
    else
        log_error "Claude Code headless 실패 (exit code: $exit_code)"
        rm -f "$temp_output"
        return 1
    fi
}

# 메인 디스패처
# IMPROVE_HEADLESS=1이면 headless, 아니면 visible 호출
claude_run() {
    local prompt_file="$1"
    local working_dir="$2"
    local done_marker_or_output="$3"
    local timeout="${4:-600}"

    if [[ "${IMPROVE_HEADLESS:-0}" == "1" ]]; then
        claude_run_headless "$prompt_file" "$working_dir" "$done_marker_or_output" "$timeout"
    else
        claude_run_visible "$prompt_file" "$working_dir" "$done_marker_or_output" "$timeout"
    fi
}
