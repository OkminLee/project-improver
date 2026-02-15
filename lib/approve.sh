#!/bin/bash
# approve.sh — 승인된 개선 항목 구현

# 메인 승인 함수
# 인자: item_ids (공백 구분, 예: "1 3 5")
run_approve() {
    local item_ids="$*"

    if [[ -z "$item_ids" ]]; then
        log_error "사용법: improve approve <item_id> [item_id2 ...]"
        return 1
    fi

    log_info "=== 개선 항목 구현 시작 ==="

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
    local project_name project_type project_path base_branch
    project_name=$(config_get "project.name")
    project_type=$(config_get "project.type")
    project_path=$(config_get "project.path")
    base_branch=$(config_get_or_default "project.branch" "main")

    local today
    today=$(date +%Y-%m-%d)

    # 최신 제안서 JSON 찾기
    local proposals_dir="$project_path/.improver/proposals"
    local latest_json

    if [[ ! -d "$proposals_dir" ]]; then
        log_error "제안서 디렉토리가 없음: $proposals_dir"
        log_error "먼저 'improve analyze'를 실행하세요"
        return 1
    fi

    latest_json=$(ls -1t "$proposals_dir"/*.json 2>/dev/null | head -1)

    if [[ -z "$latest_json" ]] || [[ ! -f "$latest_json" ]]; then
        log_error "제안서 파일을 찾을 수 없음"
        log_error "먼저 'improve analyze'를 실행하세요"
        return 1
    fi

    log_info "제안서: $latest_json"

    # 워크플로우 단계 생성
    local workflow_steps
    workflow_steps=$(python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE') as f:
        cfg = json.load(f)
    workflow = cfg.get('approve', {}).get('workflow', [])
    lines = []
    for i, step in enumerate(workflow, 1):
        if isinstance(step, str):
            lines.append(f'{i}단계 [{step}]')
        else:
            lines.append(f'{i}단계 [{step.get(\"phase\", \"단계\")}]: {step.get(\"description\", \"\")}')
    print('\n'.join(lines) if lines else '(워크플로우 설정 없음)')
except:
    print('(워크플로우 로드 실패)')
" 2>/dev/null || echo "(워크플로우 로드 실패)")

    # deploy 단계 포함 여부 확인
    local has_deploy
    has_deploy=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
workflow = cfg.get('approve', {}).get('workflow', [])
steps = [s if isinstance(s, str) else s.get('phase','') for s in workflow]
print('yes' if 'deploy' in steps else 'no')
" 2>/dev/null || echo "no")

    # deploy용 플러그인 로드
    if [[ "$has_deploy" == "yes" ]]; then
        local plugin_file="$IMPROVER_HOME/plugins/$project_type/plugin.sh"
        if [[ ! -f "$plugin_file" ]]; then
            plugin_file="$IMPROVER_HOME/plugins/generic/plugin.sh"
        fi
        if [[ -f "$plugin_file" ]]; then
            source "$plugin_file" || log_warn "플러그인 로드 실패"
        fi
    fi

    # 각 항목별 루프
    for item_id in $item_ids; do
        log_info "--- 항목 #$item_id 처리 시작 ---"

        # JSON에서 항목 추출
        local item
        item=$(json_get_array_item "$latest_json" "items" "$item_id")

        if [[ -z "$item" ]] || [[ "$item" == "null" ]]; then
            log_error "항목 #$item_id를 찾을 수 없음"
            notifier_send "항목 #$item_id 없음" "$project_name"
            continue
        fi

        # 항목 정보 파싱
        local category title description effect agent skill
        category=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin).get('category',''))")
        title=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin).get('title',''))")
        description=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin).get('description',''))")
        effect=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expectedEffect',''))")
        agent=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent',''))")
        skill=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin).get('skill',''))")

        if [[ -z "$title" ]]; then
            log_error "항목 #$item_id의 title이 비어있음"
            continue
        fi

        log_info "제목: $title"
        log_info "카테고리: $category"
        log_info "에이전트: $agent"

        # slug 생성
        local slug
        slug=$(echo "$title" | python3 -c "
import sys, re
t = sys.stdin.read().strip().lower()
t = re.sub(r'[^a-z0-9가-힣\s-]', '', t)
t = re.sub(r'\s+', '-', t)[:40]
print(t.strip('-'))
" 2>/dev/null || echo "improvement")

        local branch="improvement/$today-$slug"

        log_info "브랜치: $branch"

        # Git 브랜치 생성
        cd "$project_path" || {
            log_error "프로젝트 경로로 이동 실패: $project_path"
            continue
        }

        # 변경사항 stash
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            log_debug "로컬 변경사항 stash 중..."
            git stash push -m "improver: before item #$item_id" 2>/dev/null || true
        fi

        # base 브랜치 업데이트
        git checkout "$base_branch" 2>/dev/null || git checkout -f "$base_branch" 2>/dev/null || {
            log_error "base 브랜치 체크아웃 실패: $base_branch"
            continue
        }

        git pull origin "$base_branch" 2>/dev/null || log_warn "git pull 실패, 로컬 브랜치 사용"

        # 기존 브랜치 삭제 (있으면)
        git branch -D "$branch" 2>/dev/null || true

        # 새 브랜치 생성
        if ! git checkout -b "$branch"; then
            log_error "브랜치 생성 실패: $branch"
            notifier_send "브랜치 생성 실패: #$item_id" "$project_name"
            continue
        fi

        log_info "브랜치 '$branch' 생성 완료"
        notifier_send "구현 시작: #$item_id $title" "$project_name"

        # approve-prompt.md 템플릿 렌더링
        local template_file="$IMPROVER_HOME/templates/approve-prompt.md"

        if [[ ! -f "$template_file" ]]; then
            log_error "템플릿 파일 없음: $template_file"
            git checkout "$base_branch" 2>/dev/null || true
            continue
        fi

        local result_file="/tmp/improver-approve-result-$$-$item_id.json"

        local rendered_prompt
        rendered_prompt=$(template_render "$template_file" \
            "PROJECT_NAME=$project_name" \
            "PROJECT_TYPE=$project_type" \
            "PROJECT_PATH=$project_path" \
            "ITEM_TITLE=$title" \
            "ITEM_CATEGORY=$category" \
            "ITEM_DESCRIPTION=$description" \
            "ITEM_EFFECT=$effect" \
            "ITEM_AGENT=$agent" \
            "ITEM_SKILL=$skill" \
            "BRANCH=$branch" \
            "WORKFLOW_STEPS=$workflow_steps" \
            "RESULT_PATH=$result_file")

        if [[ -z "$rendered_prompt" ]]; then
            log_error "템플릿 렌더링 실패"
            git checkout "$base_branch" 2>/dev/null || true
            continue
        fi

        # 렌더링된 프롬프트를 임시 파일에 저장
        local prompt_file="/tmp/improver-approve-prompt-$$-$item_id.md"
        echo "$rendered_prompt" > "$prompt_file"

        log_info "프롬프트 파일 생성: $prompt_file"

        # Claude Code 실행 (타임아웃 30분)
        local done_marker="/tmp/improver-approve-done-$$-$item_id"

        log_info "Claude Code 실행 중..."

        if ! claude_run "$prompt_file" "$project_path" "$done_marker" 1800; then
            log_warn "Claude Code 실행 실패 또는 타임아웃"
            rm -f "$prompt_file" "$done_marker"
        else
            rm -f "$prompt_file" "$done_marker"
        fi

        # deploy 단계 실행
        if [[ "$has_deploy" == "yes" ]]; then
            log_info "배포 단계 실행 중..."
            if type plugin_deploy &>/dev/null; then
                if plugin_deploy "$CONFIG_FILE"; then
                    log_info "배포 성공"
                    notifier_send "배포 완료: #$item_id $title" "$project_name"
                else
                    log_warn "배포 실패"
                    notifier_send "배포 실패: #$item_id $title" "$project_name"
                fi
            else
                log_warn "plugin_deploy 함수 없음, 배포 건너뜀"
            fi
        fi

        # 결과 수집 및 알림
        if [[ -f "$result_file" ]]; then
            local pr_url build_num tf_status tf_error
            pr_url=$(python3 -c "import json; d=json.load(open('$result_file')); print(d.get('pr_url',''))" 2>/dev/null || echo "")
            build_num=$(python3 -c "import json; d=json.load(open('$result_file')); print(d.get('build_number',''))" 2>/dev/null || echo "")
            tf_status=$(python3 -c "import json; d=json.load(open('$result_file')); print(d.get('testflight',''))" 2>/dev/null || echo "")
            tf_error=$(python3 -c "import json; d=json.load(open('$result_file')); print(d.get('error',''))" 2>/dev/null || echo "")

            log_info "PR URL: $pr_url"
            log_info "Build Number: $build_num"
            log_info "TestFlight: $tf_status"

            local notify_msg="완료: #$item_id [$category] $title"
            [[ -n "$pr_url" ]] && notify_msg="$notify_msg\nPR: $pr_url"
            [[ -n "$build_num" ]] && notify_msg="$notify_msg\nBuild: #$build_num"
            [[ "$tf_status" == "success" ]] && notify_msg="$notify_msg\nTestFlight: 성공"
            [[ "$tf_status" == "failed" ]] && notify_msg="$notify_msg\nTestFlight: 실패 - $tf_error"

            notifier_send "$notify_msg" "$project_name"

            rm -f "$result_file"
        else
            if [[ -f "$done_marker" ]]; then
                log_info "Claude Code 작업 완료 (결과 상세 없음)"
                notifier_send "완료: #$item_id (결과 상세 없음)" "$project_name"
            else
                log_warn "Claude Code 타임아웃 또는 실패"
                notifier_send "경고: #$item_id 타임아웃" "$project_name"
            fi
        fi

        # base 브랜치로 복귀
        git checkout "$base_branch" 2>/dev/null || true

        log_info "--- 항목 #$item_id 처리 완료 ---"
    done

    notifier_send "전체 작업 완료 ($(echo $item_ids | wc -w | tr -d ' ')개 항목)" "$project_name"
    log_info "=== 개선 항목 구현 완료 ==="

    return 0
}
