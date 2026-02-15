#!/bin/bash
# ios/visual-helpers.sh
# Peekaboo 시각화 헬퍼 함수 — iOS 프로젝트 범용

# ── 설정 ──
VISUAL_DELAY="${VISUAL_DELAY:-1.5}"
TERMINAL_APP="${TERMINAL_APP:-Ghostty}"
UI_STEPS_DIR="${UI_STEPS_DIR:-/tmp/ios-ui-analysis}/steps"
STEP_COUNTER=0

mkdir -p "$UI_STEPS_DIR"

# ── macOS 알림 ──
notify_visual() {
    local message="$1"
    local title="${2:-iOS UI 분석}"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    echo "[NOTIFY] $message"
}

# ── 딜레이 ──
wait_visible() {
    local delay="${1:-$VISUAL_DELAY}"
    sleep "$delay"
}

# ── 단계별 스크린샷 저장 ──
capture_step() {
    local label="$1"
    STEP_COUNTER=$((STEP_COUNTER + 1))
    local filename
    filename=$(printf "%s/%02d-%s.png" "$UI_STEPS_DIR" "$STEP_COUNTER" "$label")
    peekaboo image --mode auto --path "$filename" 2>/dev/null || true
    echo "[CAPTURE] $filename"
}

# ── 윈도우 배치: Simulator 좌측, Terminal 우측 ──
arrange_windows() {
    peekaboo window set-bounds --app "Simulator" --x 0 --y 25 --width 960 --height 1055 2>/dev/null || true
    wait_visible 0.3
    peekaboo window set-bounds --app "$TERMINAL_APP" --x 960 --y 25 --width 960 --height 1055 2>/dev/null || true
    wait_visible 0.3
    echo "[ARRANGE] Simulator(좌) + $TERMINAL_APP(우)"
}

# ── Peekaboo 권한 체크 ──
check_peekaboo_permissions() {
    local result
    result=$(peekaboo permissions 2>&1)
    if echo "$result" | grep -qi "denied\|missing\|not granted"; then
        echo "ERROR: Peekaboo 권한 부족. Screen Recording + Accessibility 권한을 확인하세요."
        echo "  설정 > 개인 정보 보호 및 보안 > $TERMINAL_APP 에 권한 부여"
        notify_visual "Peekaboo 권한 부족 — 설정 확인 필요" "iOS 오류"
        return 1
    fi
    return 0
}

# ── Simulator 실행 + 앱 부팅 ──
sim_launch() {
    local app_bundle="${1:-}"

    if ! pgrep -q "Simulator"; then
        echo "[SIM] Simulator 실행 중..."
        peekaboo app launch "Simulator" 2>/dev/null || open -a Simulator
        wait_visible 3
    fi

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
        echo "[SIM] 부팅된 디바이스 없음, 기본 디바이스 부팅..."
        local default_device="${IOS_SIMULATOR:-iPhone 17 Pro}"
        xcrun simctl boot "$default_device" 2>/dev/null || true
        wait_visible 5
        booted="$default_device"
    fi

    echo "[SIM] 디바이스: $booted"

    if [[ -n "$app_bundle" ]]; then
        local launch_args="${IOS_LAUNCH_ARGS:--ScreenshotMode true}"
        xcrun simctl launch booted "$app_bundle" $launch_args 2>/dev/null || true
        wait_visible 2
    fi

    peekaboo window focus --app "Simulator" >/dev/null 2>&1 || true
    wait_visible 0.5

    echo "$booted"
}

# ── Peekaboo로 Simulator UI 맵 획득 ──
sim_see() {
    local label="${1:-current}"
    local json_path="$UI_STEPS_DIR/see-${label}.json"
    local img_path="$UI_STEPS_DIR/see-${label}.png"

    peekaboo window focus --app "Simulator" >/dev/null 2>&1 || true
    wait_visible 0.3
    peekaboo see --app "Simulator" --annotate --path "$img_path" --json \
        > "$json_path" 2>/dev/null || true

    echo "$json_path"
}

# ── UI 요소 ID 찾기 ──
find_element() {
    local json_path="$1"
    local role="$2"
    local label_contains="${3:-}"

    python3 -c "
import json, sys
try:
    with open('$json_path') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    for e in elements:
        if e.get('role') == '$role':
            if '$label_contains' == '' or '$label_contains'.lower() in str(e.get('label','')).lower():
                print(e.get('id', ''))
                sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null
}

# ── UI 요소 목록 (role 기반) ──
find_elements_by_role() {
    local json_path="$1"
    local role="$2"

    python3 -c "
import json, sys
try:
    with open('$json_path') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    for e in elements:
        if e.get('role') == '$role' and e.get('id'):
            label = e.get('label', e.get('title', '?'))
            print(f\"{e['id']}|{label}\")
except:
    pass
" 2>/dev/null
}

# ── 온보딩 화면 건너뛰기 ──
sim_dismiss_onboarding() {
    local see_json="$1"

    local onboarding_btn
    onboarding_btn=$(python3 -c "
import json, sys
try:
    with open('$see_json') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    exact_labels = ['시작하기', 'get started', '건너뛰기', 'skip', '다음', 'next', '계속', 'continue']
    for e in elements:
        eid = e.get('id', '')
        if not eid or not eid.startswith('elem_'):
            continue
        label = str(e.get('label', e.get('title', ''))).strip().lower()
        if label in [kw.lower() for kw in exact_labels]:
            print(eid)
            sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null)

    if [[ -n "$onboarding_btn" ]]; then
        echo "[NAV] 온보딩 버튼 감지: $onboarding_btn → 클릭"
        peekaboo click --on "$onboarding_btn" --app "Simulator" 2>/dev/null || true
        wait_visible 3
        return 0
    fi
    return 1
}

# ── 앱 내부 인터랙티브 요소 찾기 ──
_find_app_elements() {
    local json_path="$1"

    python3 -c "
import json, sys
try:
    with open('$json_path') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    for e in elements:
        eid = e.get('id', '')
        if not eid or not eid.startswith('elem_'):
            continue
        label = str(e.get('label', e.get('title', ''))).lower()
        skip = ['volume up', 'volume down', 'sleep/wake', 'home', 'save screen',
                'rotate', 'close button', 'full screen', 'minimize', 'action', 'toolbar']
        if any(s in label for s in skip):
            continue
        actionable = e.get('is_actionable', e.get('interactable', False))
        if actionable and label and label != 'text':
            role = e.get('role', 'other')
            print(f\"{eid}|{role}|{e.get('label', e.get('title', ''))}\")
except:
    pass
" 2>/dev/null
}

# ── Simulator 전체 화면 네비게이션 ──
NAV_COUNT_FILE="/tmp/ios-nav-count-$$.txt"

sim_navigate_all() {
    local ui_dir="$1"
    local screens_captured=0

    notify_visual "Simulator UI 탐색 시작..." "iOS UI 분석"

    echo "[NAV] 초기 화면 분석..."
    local see_json
    see_json=$(sim_see "initial")
    capture_step "initial-screen"
    screens_captured=$((screens_captured + 1))

    if sim_dismiss_onboarding "$see_json"; then
        echo "[NAV] 온보딩 건너뜀, 메인 화면 재스캔..."
        wait_visible 2
        see_json=$(sim_see "main-after-onboarding")
        capture_step "main-after-onboarding"
        screens_captured=$((screens_captured + 1))
    fi

    local tab_items
    tab_items=$(find_elements_by_role "$see_json" "tab")

    if [[ -z "$tab_items" ]]; then
        tab_items=$(python3 -c "
import json, sys
try:
    with open('$see_json') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    tab_keywords = ['홈', '서재', '통계', '설정', '검색', '탐색', 'library', 'stats', 'settings', 'search', 'explore', '기록', '목표']
    found = []
    for e in elements:
        eid = e.get('id', '')
        if not eid or not eid.startswith('elem_'):
            continue
        label = str(e.get('label', e.get('title', ''))).lower()
        for kw in tab_keywords:
            if kw == label or (len(kw) > 1 and kw in label and len(label) < 10):
                found.append(f\"{eid}|{e.get('label', e.get('title', ''))}\")
                break
    for f in found:
        print(f)
except:
    pass
" 2>/dev/null)
    fi

    if [[ -n "$tab_items" ]]; then
        echo "[NAV] 탭바 발견, 각 탭 순회..."
        local tab_index=0
        while IFS='|' read -r tab_id tab_label; do
            [[ -z "$tab_id" ]] && continue
            tab_index=$((tab_index + 1))
            echo "[NAV] 탭 $tab_index: $tab_label ($tab_id)"

            peekaboo click --on "$tab_id" --app "Simulator" 2>/dev/null || true
            wait_visible 2
            sim_see "tab-${tab_index}"
            capture_step "tab-${tab_index}-${tab_label}"
            screens_captured=$((screens_captured + 1))
        done <<< "$tab_items"

        local first_tab
        first_tab=$(echo "$tab_items" | head -1 | cut -d'|' -f1)
        if [[ -n "$first_tab" ]]; then
            peekaboo click --on "$first_tab" --app "Simulator" 2>/dev/null || true
            wait_visible
        fi
    else
        echo "[NAV] 탭바 미감지 — 앱 내부 인터랙티브 요소 직접 탐색"
        local app_elements
        app_elements=$(_find_app_elements "$see_json")
        if [[ -n "$app_elements" ]]; then
            echo "[NAV] 앱 요소 목록:"
            echo "$app_elements" | while IFS='|' read -r eid erole elabel; do
                echo "[NAV]   $eid ($erole): $elabel"
            done
        fi
    fi

    echo "[NAV] 리스트 아이템 탐색..."
    see_json=$(sim_see "pre-detail")

    local first_cell
    first_cell=$(find_element "$see_json" "cell")

    if [[ -z "$first_cell" ]]; then
        first_cell=$(python3 -c "
import json, sys
try:
    with open('$see_json') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    skip = ['volume', 'sleep', 'home', 'save screen', 'rotate', 'close button',
            'full screen', 'minimize', 'action', 'toolbar']
    for e in elements:
        eid = e.get('id', '')
        if not eid or not eid.startswith('elem_'):
            continue
        label = str(e.get('label', e.get('title', ''))).lower()
        if any(s in label for s in skip) or label == 'text':
            continue
        actionable = e.get('is_actionable', e.get('interactable', False))
        role = e.get('role', '')
        if actionable and role in ('button', 'other') and label:
            print(eid)
            sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null)
    fi

    if [[ -n "$first_cell" ]]; then
        echo "[NAV] 첫 번째 아이템 탭: $first_cell"
        peekaboo click --on "$first_cell" --app "Simulator" 2>/dev/null || true
        wait_visible 2
        sim_see "detail"
        capture_step "detail-screen"
        screens_captured=$((screens_captured + 1))

        peekaboo scroll --direction down --amount 3 --app "Simulator" 2>/dev/null || true
        wait_visible
        capture_step "detail-scrolled"
        screens_captured=$((screens_captured + 1))

        echo "[NAV] 뒤로 가기..."
        peekaboo swipe --from 10,400 --to 300,400 --app "Simulator" 2>/dev/null || true
        wait_visible 2
    else
        echo "[NAV] 탭 가능한 리스트 아이템 없음"
    fi

    echo "[NAV] 메인 화면 스크롤..."
    peekaboo scroll --direction down --amount 5 --app "Simulator" 2>/dev/null || true
    wait_visible
    sim_see "main-scrolled"
    capture_step "main-scrolled"
    screens_captured=$((screens_captured + 1))

    peekaboo scroll --direction up --amount 10 --app "Simulator" 2>/dev/null || true
    wait_visible

    notify_visual "UI 탐색 완료 (${screens_captured}개 화면 캡처)" "iOS UI 분석"
    echo "[NAV] 총 ${screens_captured}개 화면 캡처 완료"

    echo "$screens_captured" > "$NAV_COUNT_FILE"
}

# ── UI 분석 결과 요약 ──
summarize_ui_analysis() {
    local ui_dir="$1"

    local summary=""
    for json_file in "$ui_dir"/steps/see-*.json; do
        [[ -f "$json_file" ]] || continue
        local label
        label=$(basename "$json_file" .json | sed 's/see-//')

        local screen_summary
        screen_summary=$(python3 -c "
import json, sys
try:
    with open('$json_file') as f:
        data = json.load(f)
    d = data.get('data', data)
    elements = d.get('ui_elements', d.get('elements', []))
    total = len(elements)
    interactable = [e for e in elements if e.get('is_actionable') or e.get('interactable')]
    no_label = [e for e in interactable if not e.get('label') and not e.get('title')]
    small = []
    for e in interactable:
        frame = e.get('frame', {})
        if frame.get('width', 44) < 44 or frame.get('height', 44) < 44:
            small.append(e.get('label', e.get('id', '?')))
    parts = [f'요소:{total} 인터랙티브:{len(interactable)}']
    if no_label:
        parts.append(f'레이블누락:{len(no_label)}')
    if small:
        parts.append(f'작은터치:{len(small)}')
    print(' | '.join(parts))
except:
    print('분석 실패')
" 2>/dev/null)

        summary="${summary}[$label] $screen_summary\n"
    done

    echo -e "$summary"
}
