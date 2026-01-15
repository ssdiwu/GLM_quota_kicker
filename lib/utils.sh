#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 工具函数模块
# ============================================================================
# 功能：通用工具函数，时间处理、数组操作等
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_UTILS_LOADED:-}" ]] && return 0
_LIB_UTILS_LOADED=true

# 加载日志和依赖模块
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/deps.sh"

# ============================================================================
# 时间处理函数
# ============================================================================

# 计算到指定时间的等待秒数
# 参数:
#   $1 - 目标时间 (格式: HH:MM 或 HHMM)
# 返回:
#   等待的秒数
# ----------------------------------------------------------------------------
utils_calculate_wait_seconds() {
    local target_time="$1"
    local os_type
    os_type="$(dep_detect_os)"

    # 规范化时间格式
    if [[ "$target_time" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        # HHMMSS 格式 → HH:MM:SS
        target_time="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
    elif [[ "$target_time" =~ ^([0-9]{2})([0-9]{2})$ ]]; then
        # HHMM 格式 → HH:MM
        target_time="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    fi

    # 获取当前时间
    local now_epoch=$(date +%s)

    # 解析时间
    local target_hour target_minute target_second="00"

    if [[ "$target_time" =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
        target_hour="${BASH_REMATCH[1]}"
        target_minute="${BASH_REMATCH[2]}"
        target_second="${BASH_REMATCH[3]}"
    elif [[ "$target_time" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
        target_hour="${BASH_REMATCH[1]}"
        target_minute="${BASH_REMATCH[2]}"
    else
        log_error "时间格式无效: $target_time"
        return 1
    fi

    # 计算目标时间戳
    local target_epoch
    if [[ "$os_type" == "macos" ]]; then
        target_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) $target_hour:$target_minute:$target_second" +%s 2>/dev/null)
    else
        target_epoch=$(date -d "$(date +%Y-%m-%d) $target_hour:$target_minute:$target_second" +%s 2>/dev/null)
    fi

    if [[ -z "$target_epoch" ]]; then
        log_error "无法解析目标时间: $target_time"
        return 1
    fi

    # 如果目标时间已过，设置为明天
    if [[ $target_epoch -le $now_epoch ]]; then
        target_epoch=$((target_epoch + 86400))
    fi

    echo $((target_epoch - now_epoch))
}

# 格式化秒数为可读时间
# 参数:
#   $1 - 秒数
# 返回:
#   格式化的时间字符串 (如: "2小时30分15秒")
# ----------------------------------------------------------------------------
utils_format_seconds() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if [[ $hours -gt 0 ]]; then
        echo "${hours}小时${minutes}分${secs}秒"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}分${secs}秒"
    else
        echo "${secs}秒"
    fi
}

# 计算下一个时间（用于智能时间递增）
# 参数:
#   $1 - 当前时间 (格式: HH:MM)
#   $2 - 要增加的小时数
# 返回:
#   增加后的时间 (格式: HH:MM)
# ----------------------------------------------------------------------------
utils_calculate_next_time() {
    local time="$1"
    local add_hours="$2"

    # 解析小时和分钟
    local hour="${time%%:*}"
    local minute="${time##*:}"

    # 移除前导零
    hour=$((10#$hour))
    minute=$((10#$minute))

    # 增加小时数并处理跨天
    local new_hour=$(( (hour + add_hours) % 24 ))
    local new_minute=$minute

    # 格式化为两位数
    printf "%02d:%02d\n" "$new_hour" "$new_minute"
}

# ============================================================================
# 数组操作函数
# ============================================================================

# 从数组中随机选择一个元素
# 参数:
#   $1 - 数组名称
# 返回:
#   随机选择的元素
# ----------------------------------------------------------------------------
utils_random_choice() {
    local arr_name="$1"
    local count
    local result

    eval "count=\${#${arr_name}[@]}"

    if [[ $count -eq 0 ]]; then
        return 1
    fi

    local index=$((RANDOM % count))
    local ref="${arr_name}[${index}]"
    eval "result=\"\${$ref}\""
    echo "$result"
}

# ============================================================================
# 字符串处理函数
# ============================================================================

# 去除字符串首尾空格
# 参数:
#   $1 - 输入字符串
# 返回:
#   去除空格后的字符串
# ----------------------------------------------------------------------------
utils_trim() {
    local str="$1"
    # 去除前导空格
    str="${str#"${str%%[![:space:]]*}"}"
    # 去除尾部空格
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

# 检查字符串是否为空
# 参数:
#   $1 - 输入字符串
# 返回:
#   0 为空, 1 非空
# ----------------------------------------------------------------------------
utils_is_empty() {
    local str="$1"
    [[ -z "$(utils_trim "$str")" ]]
}

# ============================================================================
# 文件操作函数
# ============================================================================

# 创建临时脚本
# 参数:
#   $1 - 脚本文件路径
#   $2 - 等待秒数
#   $3 - 是否添加日志 (true/false)
# ----------------------------------------------------------------------------
utils_create_temp_script() {
    local temp_script="$1"
    local wait_seconds="$2"
    local add_log="${3:-false}"

    cat > "$temp_script" << 'EOF'
#!/bin/bash
EOF

    if [[ "$add_log" == "true" ]]; then
        cat >> "$temp_script" << EOF
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 等待 $wait_seconds 秒后执行..." >> "$LOG_FILE"
sleep $wait_seconds
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 开始执行..." >> "$LOG_FILE"
EOF
    else
        cat >> "$temp_script" << EOF
sleep $wait_seconds
EOF
    fi
}

# ============================================================================
# 进程管理函数
# ============================================================================

# 检查进程是否运行
# 参数:
#   $1 - PID 文件路径
# 返回:
#   0 运行中, 1 未运行
# ----------------------------------------------------------------------------
utils_is_pid_running() {
    local pid_file="$1"

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if ps -p "$pid" -o pid= >/dev/null 2>&1; then
            return 0
        else
            rm -f "$pid_file"
            return 1
        fi
    fi
    return 1
}
