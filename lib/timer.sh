#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 定时器模块
# ============================================================================
# 功能：一次性定时任务执行（前台/后台模式）
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_TIMER_LOADED:-}" ]] && return 0
_LIB_TIMER_LOADED=true

# 加载依赖模块
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================================
# 前台定时模式
# ============================================================================
# 参数:
#   $1 - 目标时间 (格式: HH:MM:SS, HHMMSS, HH:MM, HHMM)
# ----------------------------------------------------------------------------
timer_run_foreground() {
    local target_time="$1"

    # 规范化时间格式
    if [[ "$target_time" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        target_time="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
    elif [[ "$target_time" =~ ^([0-9]{2})([0-9]{2})$ ]]; then
        target_time="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    fi

    # 验证时间格式
    if [[ ! "$target_time" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$ ]]; then
        log_error "时间格式错误，支持格式：HH:MM:SS、HHMMSS、HH:MM 或 HHMM"
        return 1
    fi

    # 计算等待时间
    local wait_seconds
    wait_seconds=$(utils_calculate_wait_seconds "$target_time")

    if [[ -z "$wait_seconds" || $wait_seconds -lt 0 ]]; then
        log_error "无法计算等待时间"
        return 1
    fi

    local wait_str=$(utils_format_seconds "$wait_seconds")

    # 前台模式
    echo -e "${CYAN}定时模式${NC}"
    echo -e "${BLUE}目标时间: ${NC}$target_time"
    echo -e "${BLUE}等待时间: ${NC}$wait_str"
    echo -e "${YELLOW}提示: 按 Ctrl+C 取消${NC}"
    echo

    log_info "Timer task set, target time: $target_time, wait: $wait_seconds seconds"

    # 倒计时显示
    local remaining=$wait_seconds
    while [[ $remaining -gt 0 ]]; do
        if [[ $remaining -ge 60 ]]; then
            local display_min=$((remaining / 60))
            echo -ne "\r${GRAY}等待中... 剩余 ${display_min} 分钟${NC}"
        else
            echo -ne "\r${GRAY}等待中... 剩余 ${remaining} 秒${NC}"
        fi
        sleep 1
        ((remaining--))
    done
    echo -e "\n${CYAN}时间到！开始执行唤醒...${NC}"

    # 加载配置并设置消息
    config_load
    config_validate || return 1
    api_set_prompt

    # 发送请求
    api_send_request
}

# ============================================================================
# 后台定时模式
# ============================================================================
# 参数:
#   $1 - 目标时间 (格式: HH:MM:SS, HHMMSS, HH:MM, HHMM)
# ----------------------------------------------------------------------------
timer_run_background() {
    local target_time="$1"

    # 规范化时间格式
    if [[ "$target_time" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        target_time="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
    elif [[ "$target_time" =~ ^([0-9]{2})([0-9]{2})$ ]]; then
        target_time="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    fi

    # 验证时间格式
    if [[ ! "$target_time" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$ ]]; then
        log_error "时间格式错误，支持格式：HH:MM:SS、HHMMSS、HH:MM 或 HHMM"
        return 1
    fi

    # 计算等待时间
    local wait_seconds
    wait_seconds=$(utils_calculate_wait_seconds "$target_time")

    if [[ -z "$wait_seconds" || $wait_seconds -lt 0 ]]; then
        log_error "无法计算等待时间"
        return 1
    fi

    local wait_str=$(utils_format_seconds "$wait_seconds")

    # 后台模式
    echo -e "${CYAN}设置后台定时任务...${NC}"
    echo -e "${BLUE}目标时间: ${NC}$target_time"
    echo -e "${BLUE}等待时间: ${NC}$wait_str"
    echo
    echo -e "${GREEN}✓ 任务已设置，将在后台运行${NC}"
    echo -e "${CYAN}提示: 查看日志了解进度: tail -f $LOG_FILE${NC}"

    log_info "Background timer set, target time: $target_time, wait: $wait_seconds seconds"

    # 创建后台脚本（带日志）
    local temp_script="$CONFIG_DIR/.timer_wake_$$.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
# 设置必要的环境变量
export CONFIG_DIR="$CONFIG_DIR"
export LOG_FILE="$LOG_FILE"

# 记录日志
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 等待 $wait_seconds 秒后执行唤醒..." >> "\$LOG_FILE"
sleep $wait_seconds
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 开始执行唤醒..." >> "\$LOG_FILE"

# 执行唤醒并获取返回码
"\$CONFIG_DIR/bin/wake"
result=\$?

# 如果返回 2（1308 错误），创建重试任务
if [[ \$result -eq 2 && -n "\${API_RESET_TIME:-}" ]]; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 检测到配额重置时间: \${API_RESET_TIME}" >> "\$LOG_FILE"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 创建重试任务..." >> "\$LOG_FILE"

    # 在当前进程中创建重试任务
    wait_seconds=\$((60))
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 等待 \$wait_seconds 秒后重试..." >> "\$LOG_FILE"
    sleep \$wait_seconds

    # 重试唤醒
    "\$CONFIG_DIR/bin/wake" >> "\$LOG_FILE" 2>&1
fi

rm -f "$temp_script"
EOF

    chmod +x "$temp_script"

    # 后台运行
    nohup "$temp_script" >/dev/null 2>&1 &
}
