#!/bin/bash
# core.sh — project-improver 공용 함수

# 컬러 코드
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;36m'    # Cyan
readonly COLOR_WARN='\033[0;33m'    # Yellow
readonly COLOR_ERROR='\033[0;31m'   # Red
readonly COLOR_DEBUG='\033[0;90m'   # Gray

# 로깅 함수
log_info() {
    echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $*" >&2
}

log_warn() {
    echo -e "${COLOR_WARN}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "${COLOR_DEBUG}[DEBUG]${COLOR_RESET} $*" >&2
    fi
}

# JSON 필드 추출 (파일 경로, 키)
json_get() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    python3 -c "
import json, sys
try:
    with open('$file') as f:
        data = json.load(f)
    keys = '$key'.split('.')
    value = data
    for k in keys:
        value = value[k]
    print(value if value is not None else '')
except Exception as e:
    sys.exit(1)
"
}

# JSON 배열에서 id로 항목 추출 (파일 경로, 배열 키, id 값)
json_get_array_item() {
    local file="$1"
    local array_key="$2"
    local id_value="$3"

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    python3 -c "
import json, sys
try:
    with open('$file') as f:
        data = json.load(f)
    keys = '$array_key'.split('.')
    arr = data
    for k in keys:
        arr = arr[k]
    for item in arr:
        if item.get('id') == '$id_value':
            print(json.dumps(item))
            sys.exit(0)
    sys.exit(1)
except Exception as e:
    sys.exit(1)
"
}

# macOS 알림
notify() {
    local title="$1"
    local message="$2"

    if [[ "$(uname)" == "Darwin" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    fi
}

# 명령어 존재 확인
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        if [[ -n "$install_hint" ]]; then
            log_error "Install with: $install_hint"
        fi
        exit 1
    fi
}

# 디렉토리 생성
ensure_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    fi
}

# 템플릿 렌더링 (파일 경로, key=value 쌍)
# 사용 예: template_render template.txt NAME=John AGE=30
template_render() {
    local template_file="$1"
    shift

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    local content
    content=$(<"$template_file")

    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # sed로 {{key}} → value 치환
            content=$(echo "$content" | sed "s|{{$key}}|$value|g")
        else
            log_warn "Invalid key=value pair: $pair"
        fi
    done

    echo "$content"
}

# IMPROVER_HOME 자동 감지 (bin/improve에서 호출 시 설정됨)
# 이 변수는 bin/improve에서 export되어야 함
if [[ -z "${IMPROVER_HOME:-}" ]]; then
    # 라이브러리가 직접 호출된 경우, 상위 디렉토리 추정
    IMPROVER_HOME="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
fi
