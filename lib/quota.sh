#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 配额查询模块
# ============================================================================
# 功能：查询智谱 AI 配额使用情况，无需消耗配额
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_QUOTA_LOADED:-}" ]] && return 0
_LIB_QUOTA_LOADED=true

# 加载依赖模块
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# ============================================================================
# 配置
# ============================================================================
QUOTA_API_URL="https://bigmodel.cn/api/monitor/usage/quota/limit"
QUOTA_TIMEOUT="${QUOTA_TIMEOUT:-10}"

# ============================================================================
# 进度条绘制
# ============================================================================
# 参数:
#   $1 - 百分比 (0-100)
#   $2 - 进度条宽度（默认 30）
# 返回:
#   进度条字符串
# ----------------------------------------------------------------------------
quota_draw_progress_bar() {
    local percent=$1
    local width=${2:-30}
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    # 填充部分
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done

    # 空白部分
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    echo "$bar"
}

# ============================================================================
# 格式化 Token 数量
# ============================================================================
# 参数:
#   $1 - Token 数量
# 返回:
#   格式化的字符串 (如: "1.5M", "500K", "1234")
# ----------------------------------------------------------------------------
quota_format_tokens() {
    local tokens=$1

    if (( tokens >= 1000000 )); then
        local mb=$(echo "scale=1; $tokens / 1000000" | bc 2>/dev/null || echo $((tokens / 1000000)))
        echo "${mb}M"
    elif (( tokens >= 1000 )); then
        local kb=$(echo "scale=1; $tokens / 1000" | bc 2>/dev/null || echo $((tokens / 1000)))
        echo "${kb}K"
    else
        echo "$tokens"
    fi
}

# ============================================================================
# 计算剩余百分比
# ============================================================================
# 参数:
#   $1 - 已使用百分比
# 返回:
#   剩余百分比 (0-100)
# ----------------------------------------------------------------------------
quota_calc_remain_percent() {
    local used_percent=$1
    echo $((100 - used_percent))
}

# ============================================================================
# 格式化重置时间
# ============================================================================
# 参数:
#   $1 - 重置时间戳（毫秒）
# 返回:
#   格式化的时间字符串
# ----------------------------------------------------------------------------
quota_format_reset_time() {
    local reset_time_ms=$1
    local reset_time_sec=$((reset_time_ms / 1000))
    local now_sec=$(date +%s)
    local diff_sec=$((reset_time_sec - now_sec))

    if (( diff_sec <= 0 )); then
        echo "即将重置"
        return
    fi

    local hours=$((diff_sec / 3600))
    local minutes=$(((diff_sec % 3600) / 60))

    if (( hours > 0 )); then
        echo "${hours}小时${minutes}分后"
    else
        echo "${minutes}分后"
    fi
}

# ============================================================================
# 脱敏 API Key
# ============================================================================
# 参数:
#   $1 - API Key
# 返回:
#   脱敏后的 Key（显示前4位和后4位）
# ----------------------------------------------------------------------------
quota_mask_api_key() {
    local key="$1"
    local len=${#key}

    if (( len <= 8 )); then
        echo "****"
    else
        local prefix="${key:0:4}"
        local suffix="${key: -4}"
        echo "${prefix}****${suffix}"
    fi
}

# ============================================================================
# 查询配额
# ============================================================================
# 返回:
#   0 成功 (并设置全局变量)
#   1 失败
# 设置的全局变量:
#   QUOTA_TOTAL_LIMIT - 总配额
#   QUOTA_CURRENT_USED - 已使用
#   QUOTA_PERCENTAGE - 使用百分比
#   QUOTA_RESET_TIME - 重置时间戳（毫秒）
#   QUOTA_RESPONSE_JSON - 完整响应 JSON
# ----------------------------------------------------------------------------
quota_query() {
    # 确保配置已加载
    if [[ -z "${API_KEY:-}" ]]; then
        config_load || { log_error "配置加载失败"; return 1; }
    fi

    log_debug "正在查询配额: $QUOTA_API_URL"

    # 发送请求
    local response
    response=$(curl -s \
        --max-time "$QUOTA_TIMEOUT" \
        -H "Authorization: $API_KEY" \
        -H "Content-Type: application/json" \
        "$QUOTA_API_URL" 2>&1)

    local curl_exit=$?
    if [[ $curl_exit -ne 0 ]]; then
        log_error "请求失败: $response"
        return 1
    fi

    # 解析响应
    local success code msg
    success=$(echo "$response" | jq -r '.success // false' 2>/dev/null)
    code=$(echo "$response" | jq -r '.code // 0' 2>/dev/null)
    msg=$(echo "$response" | jq -r '.msg // ""' 2>/dev/null)

    if [[ "$success" != "true" ]] || [[ "$code" != "200" ]]; then
        log_error "API 返回错误: code=$code, msg=$msg"
        return 1
    fi

    # 提取数据
    export QUOTA_RESPONSE_JSON="$response"

    # 查找 TOKENS_LIMIT 类型的配额
    export QUOTA_TOTAL_LIMIT=$(echo "$response" | jq -r '.data.limits[] | select(.type=="TOKENS_LIMIT") | .usage' 2>/dev/null)
    export QUOTA_CURRENT_USED=$(echo "$response" | jq -r '.data.limits[] | select(.type=="TOKENS_LIMIT") | .currentValue' 2>/dev/null)
    export QUOTA_PERCENTAGE=$(echo "$response" | jq -r '.data.limits[] | select(.type=="TOKENS_LIMIT") | .percentage' 2>/dev/null)
    export QUOTA_RESET_TIME=$(echo "$response" | jq -r '.data.limits[] | select(.type=="TOKENS_LIMIT") | .nextResetTime // empty' 2>/dev/null)

    # 验证数据
    if [[ -z "$QUOTA_TOTAL_LIMIT" ]] || [[ "$QUOTA_TOTAL_LIMIT" == "null" ]]; then
        log_error "无法解析配额数据"
        return 1
    fi

    log_debug "配额查询成功: 已用 $QUOTA_PERCENTAGE%"
    return 0
}

# ============================================================================
# 格式化配额显示
# ============================================================================
# 返回:
#   格式化的配额信息字符串
# ----------------------------------------------------------------------------
quota_format_display() {
    local remain_percent
    remain_percent=$(quota_calc_remain_percent "${QUOTA_PERCENTAGE:-0}")
    local progress_bar
    progress_bar=$(quota_draw_progress_bar "$remain_percent")

    echo -e "\n${CYAN}═════════════════════════════════════════${NC}"
    echo -e "${CYAN}  智谱 AI 账号配额${NC}"
    echo -e "${CYAN}═════════════════════════════════════════${NC}\n"

    # 账号信息
    local masked_key
    masked_key=$(quota_mask_api_key "$API_KEY")
    echo -e "${GRAY}账号:${NC}     ${masked_key}"
    echo -e "${GRAY}模型:${NC}     ${MODEL:-unknown}"
    echo ""

    # Token 限额
    echo -e "${GRAY}5 小时 Token 限额${NC}"
    echo -e "${GREEN}${progress_bar}${NC} ${GREEN}剩余 ${remain_percent}%${NC}"

    local formatted_used formatted_total
    formatted_used=$(quota_format_tokens "${QUOTA_CURRENT_USED:-0}")
    formatted_total=$(quota_format_tokens "${QUOTA_TOTAL_LIMIT:-0}")
    echo -e "${GRAY}已用:${NC}     ${formatted_used} / ${formatted_total}"

    # 重置时间
    if [[ -n "${QUOTA_RESET_TIME:-}" ]] && [[ "$QUOTA_RESET_TIME" != "null" ]]; then
        local reset_str
        reset_str=$(quota_format_reset_time "$QUOTA_RESET_TIME")
        echo -e "${GRAY}重置:${NC}     ${reset_str}"
    fi

    echo ""

    # 警告信息
    if [[ ${QUOTA_PERCENTAGE:-0} -ge 80 ]]; then
        echo -e "${YELLOW}⚠️  配额使用率较高，请注意使用${NC}"
    elif [[ ${QUOTA_PERCENTAGE:-0} -ge 95 ]]; then
        echo -e "${RED}⚠️  配额即将耗尽！${NC}"
    elif [[ ${QUOTA_PERCENTAGE:-0} -eq 100 ]]; then
        echo -e "${RED}❌ 配额已用完！${NC}"
    else
        echo -e "${GREEN}✓ 配额状态良好${NC}"
    fi

    echo ""
}

# ============================================================================
# 检查是否已存在自动唤醒任务
# ============================================================================
# 返回:
#   0 任务存在且运行中
#   1 任务不存在或已结束
#   2 PID 文件存在但进程不存在（僵尸任务）
# 设置的全局变量:
#   AUTO_WAKE_PID - 任务 PID
#   AUTO_WAIT_SECONDS - 等待秒数
# ----------------------------------------------------------------------------
quota_check_existing_task() {
    local pid_file="$CONFIG_DIR/.auto_wake.pid"

    # 检查 PID 文件是否存在
    if [[ ! -f "$pid_file" ]]; then
        return 1
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [[ -z "$pid" ]]; then
        return 1
    fi

    # 检查进程是否存在
    if ! kill -0 "$pid" 2>/dev/null; then
        # 进程不存在，清理僵尸 PID 文件
        rm -f "$pid_file"
        # 清理可能存在的临时脚本
        rm -f "$CONFIG_DIR/.auto_wake_$pid.sh"
        return 2
    fi

    # 进程存在，获取详细信息
    export AUTO_WAKE_PID="$pid"

    # 尝试从脚本中提取等待时间
    local script_file="$CONFIG_DIR/.auto_wake_${pid}.sh"
    if [[ -f "$script_file" ]]; then
        local wait_sec
        wait_sec=$(grep -o '等待 [0-9]\+ 秒' "$script_file" 2>/dev/null | grep -o '[0-9]\+' | head -1)
        if [[ -n "$wait_sec" ]]; then
            export AUTO_WAIT_SECONDS="$wait_sec"
        fi
    fi

    return 0
}

# ============================================================================
# 自动调度唤醒任务
# ============================================================================
# 根据 QUOTA_RESET_TIME 自动设置后台定时任务
# 返回:
#   0 成功创建任务
#   1 无重置时间或创建失败
# ----------------------------------------------------------------------------
quota_schedule_auto_wake() {
    local reset_time_ms="${QUOTA_RESET_TIME:-}"

    # 检查是否有重置时间
    if [[ -z "$reset_time_ms" ]] || [[ "$reset_time_ms" == "null" ]]; then
        log_warn "没有可用的重置时间，无法自动调度"
        return 1
    fi

    # 检查是否已存在任务
    quota_check_existing_task
    local check_result=$?
    if [[ $check_result -eq 0 ]]; then
        log_warn "自动唤醒任务已存在 (PID: ${AUTO_WAKE_PID:-unknown})"
        return 1
    elif [[ $check_result -eq 2 ]]; then
        log_info "发现僵尸任务，已清理"
    fi

    # 转换为秒
    local reset_time_sec=$((reset_time_ms / 1000))
    local now_sec=$(date +%s)
    local wait_seconds=$((reset_time_sec - now_sec))

    # 如果时间已过，加上一小段时间（1分钟缓冲）
    if (( wait_seconds <= 0 )); then
        wait_seconds=60
        log_warn "重置时间已过，设置 60 秒缓冲后执行"
    fi

    # 如果等待时间太长（超过 6 小时），可能是时间戳解析错误
    if (( wait_seconds > 21600 )); then
        log_error "计算的等待时间过长: ${wait_seconds} 秒，可能是时间戳解析错误"
        return 1
    fi

    local wait_str
    wait_str=$(utils_format_seconds "$wait_seconds")

    # 创建后台脚本
    local temp_script="$CONFIG_DIR/.auto_wake_$$.sh"

    cat > "$temp_script" << EOF
#!/bin/bash
# 自动唤醒任务 - 由配额查询自动创建
# 目标时间: $(date -r $reset_time_sec '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

export CONFIG_DIR="$CONFIG_DIR"
export LOG_FILE="$LOG_FILE"

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 自动唤醒任务开始" >> "\$LOG_FILE"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 等待 ${wait_seconds} 秒后执行..." >> "\$LOG_FILE"

sleep $wait_seconds

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 配额重置时间到，开始执行唤醒..." >> "\$LOG_FILE"

# 执行唤醒
"\$CONFIG_DIR/bin/wake" >> "\$LOG_FILE" 2>&1
result=\$?

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 唤醒任务完成，返回码: \$result" >> "\$LOG_FILE"

# 清理脚本
rm -f "$temp_script"
EOF

    chmod +x "$temp_script"

    # 后台运行
    nohup "$temp_script" >/dev/null 2>&1 &

    local bg_pid=$!
    echo "$bg_pid" > "$CONFIG_DIR/.auto_wake.pid"

    log_info "自动唤醒任务已创建，PID: $bg_pid"
    return 0
}

# ============================================================================
# 格式化自动调度信息
# ----------------------------------------------------------------------------
quota_format_schedule_info() {
    local reset_time_ms="${QUOTA_RESET_TIME:-}"

    if [[ -z "$reset_time_ms" ]] || [[ "$reset_time_ms" == "null" ]]; then
        return 1
    fi

    local reset_time_sec=$((reset_time_ms / 1000))
    local reset_str
    reset_str=$(date -r $reset_time_sec '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📅 自动调度已设置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GRAY}重置时间:${NC}   $reset_str"
    echo -e "${GRAY}日志位置:${NC}   $LOG_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}
