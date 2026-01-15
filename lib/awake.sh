#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 防睡眠模块（仅 macOS）
# ============================================================================
# 功能：防止系统睡眠，确保定时任务能够正常执行
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_AWAKE_LOADED:-}" ]] && return 0
_LIB_AWAKE_LOADED=true

# 加载依赖模块
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/deps.sh"

# ============================================================================
# 防睡眠配置
# ============================================================================
CAFFEINATE_PID_FILE="$CONFIG_DIR/.caffeinate.pid"
HIBERNATE_BACKUP_FILE="$CONFIG_DIR/.hibernatemode.backup"

# ============================================================================
# 检查 caffeinate 进程是否运行
# ============================================================================
# 返回:
#   0 运行中, 1 未运行
# ----------------------------------------------------------------------------
awake_is_running() {
    utils_is_pid_running "$CAFFEINATE_PID_FILE"
}

# ============================================================================
# 启动防睡眠
# ============================================================================
# 返回:
#   0 成功, 1 失败
# ----------------------------------------------------------------------------
awake_start() {
    # 检查操作系统
    local os_type
    os_type="$(dep_detect_os)"

    if [[ "$os_type" != "macos" ]]; then
        log_warn "防睡眠功能仅支持 macOS"
        return 1
    fi

    # 检查是否已运行
    if awake_is_running; then
        log_info "防睡眠已在运行中"
        return 0
    fi

    log_info "启动防睡眠模式..."

    # 检查并保存当前的 hibernatemode 设置
    local current_hibernate_mode
    current_hibernate_mode=$(pmset -g | grep hibernatemode | awk '{print $2}')
    echo "$current_hibernate_mode" > "$HIBERNATE_BACKUP_FILE"

    # 修改 hibernatemode 为 0（禁用安全休眠）
    if [[ "$current_hibernate_mode" != "0" ]]; then
        sudo pmset -c hibernatemode 0 2>/dev/null || true
        log_info "已临时禁用安全休眠模式 (hibernatemode: $current_hibernate_mode → 0)"
    fi

    # 启动 caffeinate
    nohup caffeinate -d -s -i >/dev/null 2>&1 &
    local pid=$!

    echo "$pid" > "$CAFFEINATE_PID_FILE"

    log_success "防睡眠已启动 (PID: $pid)"
    log_info "提示: 关闭终端不影响防睡眠运行"
    log_warn "注意: 系统合盖后可能仍然会休眠"
}

# ============================================================================
# 停止防睡眠
# ============================================================================
# 返回:
#   0 成功, 1 失败
# ----------------------------------------------------------------------------
awake_stop() {
    # 检查操作系统
    local os_type
    os_type="$(dep_detect_os)"

    if [[ "$os_type" != "macos" ]]; then
        log_warn "防睡眠功能仅支持 macOS"
        return 1
    fi

    # 检查是否在运行
    if ! awake_is_running; then
        log_info "防睡眠未在运行"
        return 0
    fi

    log_info "停止防睡眠模式..."

    # 停止进程
    local pid
    pid=$(cat "$CAFFEINATE_PID_FILE")
    kill "$pid" 2>/dev/null || true
    rm -f "$CAFFEINATE_PID_FILE"

    # 恢复 hibernatemode 设置
    if [[ -f "$HIBERNATE_BACKUP_FILE" ]]; then
        local saved_hibernate_mode
        saved_hibernate_mode=$(cat "$HIBERNATE_BACKUP_FILE")
        if [[ "$saved_hibernate_mode" != "0" ]]; then
            sudo pmset -c hibernatemode "$saved_hibernate_mode" 2>/dev/null || true
            log_info "已恢复安全休眠模式 (hibernatemode: 0 → $saved_hibernate_mode)"
        fi
        rm -f "$HIBERNATE_BACKUP_FILE"
    fi

    log_success "防睡眠已停止"
}

# ============================================================================
# 显示防睡眠状态
# ============================================================================
awake_status() {
    # 检查操作系统
    local os_type
    os_type="$(dep_detect_os)"

    if [[ "$os_type" != "macos" ]]; then
        log_warn "防睡眠功能仅支持 macOS"
        return 1
    fi

    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}        防睡眠状态${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo

    if awake_is_running; then
        local pid
        pid=$(cat "$CAFFEINATE_PID_FILE")
        echo -e "状态: ${GREEN}运行中${NC}"
        echo -e "PID:  $pid"
        echo
        echo -e "${CYAN}系统将保持唤醒状态${NC}"
        echo -e "${CYAN}即使合上盖子也不会睡眠${NC}"
    else
        echo -e "状态: ${RED}未运行${NC}"
        echo
        echo -e "${YELLOW}警告: 系统可能会在合盖后睡眠${NC}"
        echo -e "${YELLOW}定时任务可能无法正常执行${NC}"
    fi

    echo
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}当前电源设置:${NC}"
    pmset -g | grep -E "sleep|displaysleep|disksleep" || true
    echo

    # 诊断提示
    local sleep_setting
    sleep_setting=$(pmset -g | grep "sleep" | grep -v "displaysleep\|disksleep\|halfsleep" | head -1 | awk '{print $2}')
    if [[ "$sleep_setting" =~ ^[0-9]+$ ]] && [[ $sleep_setting -lt 10 ]]; then
        echo -e "${YELLOW}⚠️  注意: 系统可能在合盖后仍然睡眠${NC}"
        echo -e "${GRAY}     如需防止合盖睡眠，可运行:${NC}"
        echo -e "${GRAY}     sudo pmset -c sleep 0${NC}"
        echo -e "${GRAY}     (仅在使用电源适配器时生效)${NC}"
    fi
}

# ============================================================================
# 重启防睡眠
# ============================================================================
awake_restart() {
    awake_stop
    sleep 1
    awake_start
}
