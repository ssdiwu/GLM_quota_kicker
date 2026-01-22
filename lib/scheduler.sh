#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 调度管理模块
# ============================================================================
# 功能：创建和管理系统调度任务（cron/launchd）
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_SCHEDULER_LOADED:-}" ]] && return 0
_LIB_SCHEDULER_LOADED=true

# 加载依赖模块
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/deps.sh"

# ============================================================================
# 生成 macOS launchd 配置
# ============================================================================
# 参数:
#   $1 - 时间数组名称 (包含多个 HH:MM 格式的时间)
# ----------------------------------------------------------------------------
scheduler_generate_macos_launchd() {
    local times_name="$1"
    eval "local -a times=(\"\${$times_name[@]}\")"

    local plist_path="$HOME/Library/LaunchAgents/com.GLM_quota_kicker.plist"
    local script_path="$CONFIG_DIR/bin/wake"

    # 解析第一个时间点
    local first_hour="${times[0]%%:*}"
    local first_minute="${times[0]##*:}"

    # 创建 plist 文件
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.GLM_quota_kicker</string>
    <key>ProgramArguments</key>
    <array>
        <string>$script_path</string>
    </array>
EOF

    # 根据时间点数量选择正确的格式
    if [[ ${#times[@]} -eq 1 ]]; then
        # 单个时间点：使用字典格式（更兼容）
        cat >> "$plist_path" << EOF
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$first_hour</integer>
        <key>Minute</key>
        <integer>$first_minute</integer>
    </dict>
EOF
    else
        # 多个时间点：使用数组格式
        cat >> "$plist_path" << EOF
    <key>StartCalendarInterval</key>
    <array>
EOF
        for time in "${times[@]}"; do
            local hour="${time%%:*}"
            local minute="${time##*:}"
            cat >> "$plist_path" << EOF
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
EOF
        done
        cat >> "$plist_path" << EOF
    </array>
EOF
    fi

    # 结束 plist 文件
    cat >> "$plist_path" << EOF
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
EOF

    # 加载 launchd
    launchctl unload "$plist_path" 2>/dev/null || true
    launchctl load "$plist_path"

    log_info "macOS 调度任务已配置"
}

# ============================================================================
# 生成 Linux cron 配置
# ============================================================================
# 参数:
#   $1 - 时间数组名称 (包含多个 HH:MM 格式的时间)
# ----------------------------------------------------------------------------
scheduler_generate_linux_cron() {
    local times_name="$1"
    eval "local -a times=(\"\${$times_name[@]}\")"

    local script_path="$CONFIG_DIR/bin/wake"
    local cron_entry=""

    # 构建 cron 条目
    for time in "${times[@]}"; do
        local hour="${time%%:*}"
        local minute="${time##*:}"
        cron_entry="$cron_entry$minute $hour * * * $script_path\n"
    done

    # 添加到 crontab
    (crontab -l 2>/dev/null | grep -v "GLM_quota_kicker"; echo -e "$cron_entry") | crontab -

    log_info "Linux cron 任务已配置"
}

# ============================================================================
# 创建调度任务
# ============================================================================
# 参数:
#   $@ - 多个时间 (格式: HH:MM)
# ----------------------------------------------------------------------------
scheduler_create() {
    local -a times=("$@")

    if [[ ${#times[@]} -eq 0 ]]; then
        log_error "至少需要提供一个时间"
        return 1
    fi

    log_info "正在配置系统调度任务..."

    local os_type
    os_type="$(dep_detect_os)"

    # 根据操作系统类型调用相应的配置函数
    if [[ "$os_type" == "macos" ]]; then
        scheduler_generate_macos_launchd times
    elif [[ "$os_type" == "linux" ]]; then
        scheduler_generate_linux_cron times
    else
        log_error "不支持的操作系统: $os_type"
        return 1
    fi

    # 保存调度时间到文件
    echo "${times[*]}" > "$SCHEDULE_FILE"
}

# ============================================================================
# 取消调度任务
# ============================================================================
scheduler_remove() {
    log_info "正在取消调度任务..."

    local os_type
    os_type="$(dep_detect_os)"

    if [[ "$os_type" == "macos" ]]; then
        local plist_path="$HOME/Library/LaunchAgents/com.GLM_quota_kicker.plist"
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        log_info "macOS 调度任务已取消"
    elif [[ "$os_type" == "linux" ]]; then
        crontab -l | grep -v "GLM_quota_kicker" | crontab -
        log_info "Linux cron 任务已取消"
    fi

    rm -f "$SCHEDULE_FILE"
}

# ============================================================================
# 列出当前调度任务
# ============================================================================
scheduler_list() {
    local os_type
    os_type="$(dep_detect_os)"

    echo "当前调度任务:"
    echo

    if [[ "$os_type" == "macos" ]]; then
        if launchctl list | grep -q "GLM_quota_kicker"; then
            echo "macOS LaunchAgent 任务:"
            launchctl list | grep "GLM_quota_kicker"
        else
            echo "未配置调度任务"
        fi
    elif [[ "$os_type" == "linux" ]]; then
        local cron_jobs
        cron_jobs=$(crontab -l 2>/dev/null | grep "GLM_quota_kicker" || true)
        if [[ -n "$cron_jobs" ]]; then
            echo "Cron 任务:"
            echo "$cron_jobs"
        else
            echo "未配置调度任务"
        fi
    fi

    # 显示配置的时间
    if [[ -f "$SCHEDULE_FILE" ]]; then
        echo
        echo "配置的时间: $(cat "$SCHEDULE_FILE")"
    fi
}

# ============================================================================
# 创建一次性重试任务（用于 1308 错误后）
# ============================================================================
# 参数:
#   $1 - 重置时间 (格式: YYYY-MM-DD HH:MM:SS)
# ----------------------------------------------------------------------------
scheduler_create_retry_task() {
    local reset_time="$1"
    local os_type
    os_type="$(dep_detect_os)"

    # 计算等待秒数（添加 60 秒缓冲时间，确保配额已重置）
    local reset_epoch now_epoch wait_seconds
    if [[ "$os_type" == "macos" ]]; then
        reset_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$reset_time" +%s 2>/dev/null)
    else
        reset_epoch=$(date -d "$reset_time" +%s 2>/dev/null)
    fi

    now_epoch=$(date +%s)
    # 添加 60 秒缓冲时间，确保配额已完全重置
    wait_seconds=$((reset_epoch - now_epoch + 60))

    if [[ $wait_seconds -le 0 ]]; then
        # 如果计算出的等待时间为负或零，说明时间已过，等待 60 秒后重试
        wait_seconds=60
    fi

    local wait_str
    wait_str=$(utils_format_seconds "$wait_seconds")

    echo -e "${YELLOW}→ 配额将在 $reset_time 重置${NC}"
    echo -e "${CYAN}→ 已安排自动重试，将在 ${wait_str} 后执行（含 60 秒缓冲时间）${NC}"

    # 创建一次性调度脚本（带智能重试机制）
    local temp_script="$CONFIG_DIR/.retry_wake.sh"
    cat > "$temp_script" << RETRY_SCRIPT
#!/bin/bash

# 配置重试参数
MAX_ATTEMPTS=5
RETRY_INTERVAL=20
WAIT_SECONDS=$wait_seconds

# 记录开始等待
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 等待 \$WAIT_SECONDS 秒后执行唤醒..." >> "$LOG_FILE"

# 等待到重置时间之后
sleep \$WAIT_SECONDS

# 尝试多次唤醒，直到成功或达到最大次数
for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 第 \$attempt 次尝试唤醒..." >> "\$LOG_FILE"

    # 执行唤醒
    "\$CONFIG_DIR/bin/wake" >> "\$LOG_FILE" 2>&1
    result=\$?

    # 检查结果
    if [[ \$result -eq 0 ]]; then
        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✓ 唤醒成功！" >> "\$LOG_FILE"
        break
    elif [[ \$result -eq 2 ]]; then
        # 仍然是 1308 错误，继续重试
        if [[ \$attempt -lt \$MAX_ATTEMPTS ]]; then
            echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 配额仍未重置，\${RETRY_INTERVAL}秒后第 \$((attempt + 1)) 次尝试..." >> "\$LOG_FILE"
            sleep \$RETRY_INTERVAL
        else
            echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✗ 已重试 \$MAX_ATTEMPTS 次仍未成功，请稍后手动重试" >> "\$LOG_FILE"
        fi
    else
        # 其他错误，直接退出
        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✗ 唤醒失败（错误码: \$result）" >> "\$LOG_FILE"
        break
    fi
done

# 清理临时脚本
rm -f "\$0"
RETRY_SCRIPT

    chmod +x "$temp_script"

    # 后台运行
    nohup "$temp_script" >/dev/null 2>&1 &

    log_info "[错误码 1308] 已安排自动重试: 将在 $reset_time 后执行（含 60 秒缓冲 + 智能重试）"
}
