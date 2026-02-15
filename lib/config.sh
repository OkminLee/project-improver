#!/bin/bash
# config.sh — .improver/config.json 로드 및 검증

# 전역 변수
CONFIG_FILE=""
CONFIG_JSON=""

# 설정 로드
config_load() {
    local search_dir="${1:-.}"

    # .improver/config.json 찾기
    local config_path="$search_dir/.improver/config.json"

    if [[ ! -f "$config_path" ]]; then
        log_error "Configuration file not found: $config_path"
        log_error "Run 'improve init' to create a new project configuration"
        return 1
    fi

    # JSON 유효성 검증
    if ! python3 -c "import json; json.load(open('$config_path'))" 2>/dev/null; then
        log_error "Invalid JSON in configuration file: $config_path"
        return 1
    fi

    CONFIG_FILE="$config_path"
    CONFIG_JSON=$(<"$config_path")

    log_debug "Configuration loaded from: $config_path"
    return 0
}

# 설정 값 추출 (dot notation)
config_get() {
    local key="$1"

    if [[ -z "$CONFIG_FILE" ]]; then
        log_error "Configuration not loaded. Call config_load first"
        return 1
    fi

    json_get "$CONFIG_FILE" "$key"
}

# 설정 값 추출 (기본값 포함)
config_get_or_default() {
    local key="$1"
    local default="$2"

    local value
    value=$(config_get "$key" 2>/dev/null)

    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# 설정 검증
config_validate() {
    if [[ -z "$CONFIG_FILE" ]]; then
        log_error "Configuration not loaded. Call config_load first"
        return 1
    fi

    local required_fields=(
        "project.name"
        "project.type"
        "project.path"
    )

    local has_error=0

    for field in "${required_fields[@]}"; do
        local value
        value=$(config_get "$field" 2>/dev/null)

        if [[ -z "$value" ]]; then
            log_error "Missing required field: $field"
            has_error=1
        fi
    done

    if [[ $has_error -eq 1 ]]; then
        return 1
    fi

    # 프로젝트 경로 존재 확인
    local project_path
    project_path=$(config_get "project.path")

    if [[ ! -d "$project_path" ]]; then
        log_error "Project path does not exist: $project_path"
        return 1
    fi

    log_debug "Configuration validation passed"
    return 0
}

# 프로젝트 타입 자동 감지
config_detect_type() {
    local project_path="${1:-.}"

    if [[ ! -d "$project_path" ]]; then
        log_error "Directory not found: $project_path"
        return 1
    fi

    # iOS 프로젝트 감지
    if find "$project_path" -maxdepth 2 -name "*.xcodeproj" -print -quit | grep -q .; then
        echo "ios"
        return 0
    fi

    # Web 프로젝트 감지
    if [[ -f "$project_path/package.json" ]]; then
        echo "web"
        return 0
    fi

    # Android 프로젝트 감지
    if [[ -f "$project_path/build.gradle" ]] || [[ -f "$project_path/build.gradle.kts" ]]; then
        echo "android"
        return 0
    fi

    # 기본값
    echo "generic"
    return 0
}
