#!/bin/bash
# ios/plugin.sh — iOS 프로젝트 플러그인

# visual-helpers.sh 로드
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_DIR/visual-helpers.sh"

plugin_detect() {
    local project_path="${1:-.}"

    if [[ -n "$(find "$project_path" -maxdepth 2 -name "*.xcodeproj" -o -name "*.xcworkspace" 2>/dev/null)" ]]; then
        return 0
    fi

    return 1
}

plugin_build() {
    local config_file="${1:-}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log_error "Config file required for iOS build"
        return 1
    fi

    local project_path
    project_path=$(json_get "$config_file" "project.path")

    local scheme
    scheme=$(json_get "$config_file" "ios.scheme" 2>/dev/null || echo "")

    local simulator
    simulator=$(json_get "$config_file" "ios.simulator" 2>/dev/null || echo "iPhone 17 Pro")

    local bundle_id
    bundle_id=$(json_get "$config_file" "ios.bundleId" 2>/dev/null || echo "")

    local screenshot_mode
    screenshot_mode=$(json_get "$config_file" "ios.screenshotMode" 2>/dev/null || echo "true")

    if [[ -z "$scheme" ]]; then
        local xcodeproj
        xcodeproj=$(find "$project_path" -maxdepth 2 -name "*.xcodeproj" 2>/dev/null | head -1)
        if [[ -n "$xcodeproj" ]]; then
            scheme=$(basename "$xcodeproj" .xcodeproj)
        else
            log_error "No scheme configured and cannot detect from project"
            return 1
        fi
    fi

    log_info "iOS 빌드 시작: $scheme (device: $simulator)"

    local booted
    booted=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for rt in d.get('devices',{}).values():
    for dev in rt:
        if dev.get('state')=='Booted':
            print(dev['name']); sys.exit(0)
" 2>/dev/null || echo "")

    if [[ -z "$booted" ]]; then
        log_info "Simulator 부팅 중 ($simulator)..."
        xcrun simctl boot "$simulator" 2>/dev/null || true
        open -a Simulator
        sleep 5
    fi

    local running_bundle
    if [[ -n "$bundle_id" ]]; then
        running_bundle=$(xcrun simctl listapps booted 2>/dev/null | python3 -c "
import plistlib, sys
try:
    data = plistlib.load(sys.stdin.buffer)
    for bid, info in data.items():
        if '$bundle_id' in bid:
            print(bid); sys.exit(0)
except: pass
" 2>/dev/null || echo "")

        if [[ -n "$running_bundle" ]]; then
            xcrun simctl terminate booted "$running_bundle" 2>/dev/null || true
            log_info "이전 앱 종료: $running_bundle"
        fi
    fi

    local xcodeproj_file
    xcodeproj_file=$(find "$project_path" -maxdepth 2 -name "*.xcodeproj" 2>/dev/null | head -1)

    local build_log="$UI_STEPS_DIR/xcodebuild.log"
    mkdir -p "$(dirname "$build_log")"

    log_info "xcodebuild -scheme $scheme 빌드 중..."

    if xcodebuild -project "$xcodeproj_file" \
        -scheme "$scheme" \
        -destination "platform=iOS Simulator,name=$simulator" \
        -derivedDataPath "$project_path/.build" \
        build 2>&1 | tee "$build_log" | grep -E "^(Build|Compile|Link|error:|warning:|\*\*)" ; then
        log_info "빌드 성공"
    else
        log_error "빌드 실패 — 로그: $build_log"
        return 1
    fi

    local app_path
    app_path=$(find "$project_path/.build" -name "*.app" -path "*/Debug-iphonesimulator/*" -not -path "*/PlugIns/*" -maxdepth 6 2>/dev/null | head -1)

    if [[ -z "$app_path" ]]; then
        log_error ".app 파일을 찾을 수 없음"
        return 1
    fi

    log_info "설치: $(basename "$app_path")"
    xcrun simctl install booted "$app_path" 2>/dev/null || true

    if [[ -z "$bundle_id" ]]; then
        bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist" 2>/dev/null || echo "")
    fi

    if [[ -n "$bundle_id" ]]; then
        local launch_args=""
        if [[ "$screenshot_mode" == "true" ]]; then
            launch_args="-ScreenshotMode true"
        fi

        log_info "실행: $bundle_id $launch_args"
        xcrun simctl launch booted "$bundle_id" $launch_args 2>/dev/null || true
        sleep 3
    fi

    local elapsed=0
    while [[ $elapsed -lt 30 ]]; do
        sleep 3
        elapsed=$((elapsed + 3))
        local element_count
        element_count=$(peekaboo see --app "Simulator" --json 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    els=d.get('data',d).get('ui_elements',d.get('elements',[]))
    print(len(els))
except: print(0)
" 2>/dev/null || echo "0")
        if [[ "$element_count" -gt 3 ]]; then
            log_info "앱 로드 감지 (UI 요소: $element_count)"
            return 0
        fi
    done

    log_info "앱 로드 확인 (UI 감지 불확실, 계속 진행)"
    return 0
}

plugin_ui_analysis() {
    if ! check_peekaboo_permissions; then
        echo "Peekaboo 권한 없음 — 코드 기반 분석만 수행"
        return 0
    fi

    local ui_dir="${UI_STEPS_DIR%/steps}"

    log_info "Peekaboo UI 분석 시작..."
    sim_navigate_all "$ui_dir"

    local screens_captured=0
    if [[ -f "$NAV_COUNT_FILE" ]]; then
        screens_captured=$(cat "$NAV_COUNT_FILE")
        rm -f "$NAV_COUNT_FILE"
    fi

    log_info "UI 분석 요약 생성..."
    summarize_ui_analysis "$ui_dir"

    log_info "UI 분석 완료 (${screens_captured}개 화면)"
    return 0
}

plugin_deploy() {
    local config_file="${1:-}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log_warn "No config file provided, skipping deploy"
        return 0
    fi

    local deploy_cmd
    deploy_cmd=$(json_get "$config_file" "ios.deployCommand" 2>/dev/null || echo "")

    if [[ -z "$deploy_cmd" ]]; then
        log_info "No ios.deployCommand configured, skipping deploy"
        return 0
    fi

    log_info "Running deploy: $deploy_cmd"
    eval "$deploy_cmd"
}
