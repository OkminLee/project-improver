#!/bin/bash
# generic/plugin.sh — 범용 프로젝트 플러그인 (폴백)

plugin_detect() {
    # 항상 true 반환 (폴백 플러그인)
    return 0
}

plugin_build() {
    local config_file="${1:-}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log_warn "No config file provided, skipping build"
        return 0
    fi

    local build_cmd
    build_cmd=$(json_get "$config_file" "generic.buildCommand" 2>/dev/null || echo "")

    if [[ -z "$build_cmd" ]]; then
        log_info "No generic.buildCommand configured, skipping build"
        return 0
    fi

    log_info "Running build: $build_cmd"
    eval "$build_cmd"
}

plugin_ui_analysis() {
    echo "UI 분석 없음 — 코드 기반 분석만 수행"
    return 0
}

plugin_deploy() {
    local config_file="${1:-}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log_warn "No config file provided, skipping deploy"
        return 0
    fi

    local deploy_cmd
    deploy_cmd=$(json_get "$config_file" "generic.deployCommand" 2>/dev/null || echo "")

    if [[ -z "$deploy_cmd" ]]; then
        log_info "No generic.deployCommand configured, skipping deploy"
        return 0
    fi

    log_info "Running deploy: $deploy_cmd"
    eval "$deploy_cmd"
}
