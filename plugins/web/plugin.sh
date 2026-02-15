#!/bin/bash
# web/plugin.sh — 웹 프로젝트 플러그인

plugin_detect() {
    local project_path="${1:-.}"

    if [[ -f "$project_path/package.json" ]]; then
        return 0
    fi

    return 1
}

plugin_build() {
    local config_file="${1:-}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log_error "Config file required for web build"
        return 1
    fi

    local project_path
    project_path=$(json_get "$config_file" "project.path")

    local build_cmd
    build_cmd=$(json_get "$config_file" "web.buildCommand" 2>/dev/null || echo "npm run build")

    log_info "웹 빌드 시작: $build_cmd"

    cd "$project_path" || return 1
    eval "$build_cmd"
}

plugin_ui_analysis() {
    echo "웹 UI 분석은 수동 확인이 필요합니다"
    echo "향후 Lighthouse 통합 예정"
    return 0
}

plugin_deploy() {
    local config_file="${1:-}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log_warn "No config file provided, skipping deploy"
        return 0
    fi

    local project_path
    project_path=$(json_get "$config_file" "project.path")

    local deploy_cmd
    deploy_cmd=$(json_get "$config_file" "web.deployCommand" 2>/dev/null || echo "")

    if [[ -z "$deploy_cmd" ]]; then
        log_info "No web.deployCommand configured, skipping deploy"
        return 0
    fi

    log_info "Running deploy: $deploy_cmd"

    cd "$project_path" || return 1
    eval "$deploy_cmd"
}
