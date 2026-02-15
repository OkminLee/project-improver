#!/bin/bash
# analyze.sh — 프로젝트 분석 및 개선 제안서 생성

# 메인 분석 함수
run_analyze() {
    log_info "=== 프로젝트 분석 시작 ==="

    # 설정 로드 및 검증
    if ! config_load; then
        log_error "설정 로드 실패"
        return 1
    fi

    if ! config_validate; then
        log_error "설정 검증 실패"
        return 1
    fi

    # 프로젝트 정보 추출
    local project_name project_type project_path
    project_name=$(config_get "project.name")
    project_type=$(config_get "project.type")
    project_path=$(config_get "project.path")

    local max_items
    max_items=$(config_get_or_default "analyze.max_items" "5")

    local today
    today=$(date +%Y-%m-%d)

    # 출력 경로 준비
    local output_dir output_path
    output_dir="$project_path/.improver/proposals"
    output_path="$output_dir/$today.json"

    ensure_dir "$output_dir" || return 1

    log_info "프로젝트: $project_name ($project_type)"
    log_info "경로: $project_path"
    log_info "최대 항목 수: $max_items"

    # 프로젝트 타입에 맞는 플러그인 로드
    local plugin_file="$IMPROVER_HOME/plugins/$project_type/plugin.sh"

    if [[ ! -f "$plugin_file" ]]; then
        log_warn "플러그인 파일 없음: $plugin_file (generic으로 폴백)"
        plugin_file="$IMPROVER_HOME/plugins/generic/plugin.sh"
    fi

    if [[ -f "$plugin_file" ]]; then
        log_debug "플러그인 로드: $plugin_file"
        source "$plugin_file" || {
            log_warn "플러그인 로드 실패, 계속 진행"
        }
    else
        log_warn "플러그인 없음, UI 분석 건너뜀"
    fi

    # 플러그인 빌드 (실패해도 계속 진행)
    local ui_context=""
    if type plugin_build &>/dev/null; then
        log_info "플러그인 빌드 실행 중..."
        notifier_send "프로젝트 빌드 시작" "$project_name"

        if plugin_build "$CONFIG_FILE"; then
            log_info "플러그인 빌드 성공"
        else
            log_warn "플러그인 빌드 실패, UI 분석 건너뜀"
        fi
    else
        log_debug "plugin_build 함수 없음, 빌드 건너뜀"
    fi

    # UI 분석 (플러그인 함수 호출)
    if type plugin_ui_analysis &>/dev/null; then
        log_info "UI 분석 실행 중..."
        notifier_send "UI 분석 중" "$project_name"

        ui_context=$(plugin_ui_analysis "$CONFIG_FILE") || ui_context=""

        if [[ -z "$ui_context" ]]; then
            log_warn "UI 분석 결과 없음"
            ui_context="UI 분석을 수행할 수 없었습니다. 코드 기반으로만 분석해주세요."
        else
            log_info "UI 분석 완료"
        fi
    else
        log_debug "plugin_ui_analysis 함수 없음, UI 분석 건너뜀"
        ui_context="UI 분석이 지원되지 않는 프로젝트 타입입니다."
    fi

    # 에이전트 목록 생성
    local agents_list
    agents_list=$(python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE') as f:
        cfg = json.load(f)
    agents = cfg.get('analyze', {}).get('agents', [])
    lines = []
    for a in agents:
        name = a.get('name', '')
        desc = a.get('description', '')
        skill = a.get('skill', '')
        if name:
            lines.append(f'- {name}: {desc}' + (f' (skill: {skill})' if skill else ''))
    print('\n'.join(lines) if lines else '- (에이전트 설정 없음)')
except:
    print('- (에이전트 목록 로드 실패)')
" 2>/dev/null || echo "- (에이전트 목록 로드 실패)")

    # analyze-prompt.md 템플릿 렌더링
    local template_file="$IMPROVER_HOME/templates/analyze-prompt.md"

    if [[ ! -f "$template_file" ]]; then
        log_error "템플릿 파일 없음: $template_file"
        return 1
    fi

    local rendered_prompt
    rendered_prompt=$(template_render "$template_file" \
        "PROJECT_NAME=$project_name" \
        "PROJECT_TYPE=$project_type" \
        "PROJECT_PATH=$project_path" \
        "UI_CONTEXT=$ui_context" \
        "MAX_ITEMS=$max_items" \
        "TODAY=$today" \
        "OUTPUT_PATH=$output_path" \
        "AGENTS_LIST=$agents_list")

    if [[ -z "$rendered_prompt" ]]; then
        log_error "템플릿 렌더링 실패"
        return 1
    fi

    # 렌더링된 프롬프트를 임시 파일에 저장
    local prompt_file="/tmp/improver-analyze-prompt-$$.md"
    echo "$rendered_prompt" > "$prompt_file"

    log_info "프롬프트 파일 생성: $prompt_file"

    # Claude Code 실행
    local done_marker="/tmp/improver-analyze-done-$$"

    notifier_send "Claude Code 분석 시작" "$project_name"
    log_info "Claude Code 실행 중..."

    if ! claude_run "$prompt_file" "$project_path" "$done_marker" 600; then
        log_error "Claude Code 실행 실패"
        rm -f "$prompt_file" "$done_marker"
        notifier_send "분석 실패" "$project_name"
        return 1
    fi

    rm -f "$prompt_file" "$done_marker"

    # 결과 JSON 검증
    if [[ ! -f "$output_path" ]]; then
        log_error "결과 파일이 생성되지 않음: $output_path"
        notifier_send "분석 실패: 결과 없음" "$project_name"
        return 1
    fi

    local json_content
    json_content=$(<"$output_path")

    if [[ -z "$json_content" ]]; then
        log_error "결과 파일이 비어있음"
        notifier_send "분석 실패: 빈 결과" "$project_name"
        return 1
    fi

    # JSON 유효성 검증
    if ! python3 -c "import json; json.loads('''$json_content''')" 2>/dev/null; then
        log_error "결과가 유효한 JSON이 아님"
        notifier_send "분석 실패: 잘못된 JSON" "$project_name"
        return 1
    fi

    # 항목 수 확인
    local item_count
    item_count=$(python3 -c "
import json
data = json.loads('''$json_content''')
print(len(data.get('items', [])))
" 2>/dev/null || echo "0")

    log_info "분석 완료: $item_count개 개선 항목 생성"
    log_info "결과 저장: $output_path"

    notifier_send "분석 완료: ${item_count}개 항목" "$project_name"

    return 0
}
