# 错误经验总结文档

本文档记录开发过程中遇到的关键错误及解决方案，避免后续重复犯错。

## 1. Bash 数组作用域问题（bash 3.2）

### 问题描述
在函数内部使用 `export PROMPTS_ARRAY=()` 声明并填充数组后，函数外部无法访问数组元素。

### 错误代码
```bash
config_load() {
    # ...
    export PROMPTS_ARRAY=()  # ❌ 错误：函数内export的数组在函数外不可访问
    while IFS= read -r line; do
        PROMPTS_ARRAY+=("$line")
    done <<< "$data"
}
```

### 正确做法
```bash
config_load() {
    # ...
    unset PROMPTS_ARRAY      # 先清除旧数组
    PROMPTS_ARRAY=()         # 不使用export声明
    while IFS= read -r line; do
        PROMPTS_ARRAY+=("$line")
    done < <(printf '%s' "$data")
    export PROMPTS_ARRAY     # 填充完成后再export
}
```

### 关键要点
- bash 3.2 中，`export ARRAY=()` 在函数内创建的是局部数组
- 必须先声明并填充数组，再 export
- 使用 `unset` 清除可能存在的旧数组

---

## 2. process substitution 与 here-string 的换行问题

### 问题描述
使用 `<<< "$data"` (here-string) 时，会额外添加换行符，导致 while 循环读取到空行。

### 错误代码
```bash
while IFS= read -r line; do
    [[ -n "$line" ]] && ARRAY+=("$line")
done <<< "$prompts_raw"  # ❌ 可能产生前导空行
```

### 正确做法
```bash
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue  # 显式跳过空行
    ARRAY+=("$line")
done < <(printf '%s' "$prompts_raw")  # 使用printf避免额外换行
```

### 关键要点
- `echo "$data"` 会在末尾添加换行符
- `printf '%s' "$data"` 不会添加额外换行
- `|| [[ -n "$line" ]]` 处理最后一行没有换行的情况
- 显式使用 `[[ -z "$line" ]] && continue` 跳过空行

---

## 3. bash 3.2 不支持 nameref

### 问题描述
使用 `local -n` (nameref) 功能在 bash 3.2 中报错 "bad option"。

### 错误代码
```bash
utils_random_choice() {
    local -n arr_ref="$arr_name"  # ❌ bash 3.2 不支持
    result="${arr_ref[$index]}"
}
```

### 正确做法
```bash
utils_random_choice() {
    local ref="${arr_name}[${index}]"
    eval "result=\"\${$ref}\""
}
```

### 关键要点
- nameref (`-n`) 是 bash 4.3+ 的功能
- macOS 默认 bash 3.2.57 不支持
- 使用 `eval` 实现间接变量引用以保持兼容性
- 检查环境：`bash --version`

---

## 4. 测试不足导致的问题

### 问题描述
只做语法检查 (`bash -n`) 不做功能测试，导致运行时错误未被发现。

### 错误流程
```bash
bash -n file.sh  # ❌ 只检查语法，未测试实际运行
echo "修复完成"
```

### 正确流程
```bash
# 1. 语法检查
bash -n file.sh

# 2. 功能测试
./script.sh --test

# 3. 边界测试
./script.sh --test 2>&1 | grep -v "正常输出"

# 4. 集成测试
for i in {1..5}; do ./script.sh --test; done
```

### 关键要点
- 语法检查 ≠ 功能正常
- 必须进行端到端测试
- 验证变量值、数组内容、函数返回值
- 多次运行确保稳定性

---

## 5. eval 嵌套变量引用的转义

### 问题描述
eval 中的嵌套变量引用转义不正确，导致字面量字符串而非实际值。

### 错误代码
```bash
eval "result=\${${arr_name}[${index}]}"  # ❌ 转义不正确
```

### 正确做法
```bash
local ref="${arr_name}[${index}]"
eval "result=\"\${$ref}\""
```

### 关键要点
- 先构建变量引用字符串
- 再通过 eval 展开最终的值
- 使用 `\$` 延迟展开

---

## 开发检查清单

在修改代码后，按以下顺序检查：

1. [ ] 语法检查：`bash -n file.sh`
2. [ ] 功能测试：实际运行脚本
3. [ ] 变量验证：使用 `declare -p VAR` 检查
4. [ ] 数组验证：检查 `${#ARRAY[@]}` 和 `${ARRAY[0]}`
5. [ ] 多次运行：确保稳定性
6. [ ] 边界测试：空输入、特殊字符等
7. [ ] 文档更新：同步更新相关文档

---

## 兼容性注意事项

- macOS 默认 bash 3.2.57
- 避免使用 bash 4.0+ 特性：
  - `local -n` (nameref, 4.3+)
  - `declare -g` (4.2+)
  - `readarray` (4.0+)
  - 某些参数扩展
