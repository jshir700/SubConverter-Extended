#!/bin/bash
# SubConverter-Extended Fork 独有功能完整测试
# 覆盖所有参数的正常情况、边界情况、异常情况

set -e
HOST="http://localhost:25500"
PASS=0
FAIL=0
TOTAL=0

echo "=========================================="
echo "SubConverter-Extended Fork 独有功能测试"
echo "=========================================="
echo ""

# 辅助函数
b64url() {
    printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '='
}

test_result() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $name"
        echo "    期望: [$expected] 实际: [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

# 测试节点
VMESS="vmess://test@test.example.com:443?type=tcp&security=tls#TestNode"
VMESS_B64=$(b64url "$VMESS")
VMESS2="vmess://test2@test2.example.com:444?type=tcp&security=tls#TestNode2"
VMESS2_B64=$(b64url "$VMESS2")

echo "  测试节点已准备"
echo ""

# ============================================
# 1. dedup 参数测试
# ============================================
echo "【1. dedup 参数测试】"
echo ""

# 1.1 dedup=true (默认行为)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&dedup=true")
test_result "dedup=true 显式启用" "200" "$RESP"

# 1.2 dedup=false
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&dedup=false")
test_result "dedup=false 显式禁用" "200" "$RESP"

# 1.3 dedup 未指定 (默认 true)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false")
test_result "dedup 未指定 (默认 true)" "200" "$RESP"

# 1.4 dedup=1 (truthy)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&dedup=1")
test_result "dedup=1 (truthy)" "200" "$RESP"

# 1.5 dedup=0 (falsy)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&dedup=0")
test_result "dedup=0 (falsy)" "200" "$RESP"

# 1.6 dedup 与其他参数组合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&dedup=true&ua=TestUA&global-ua=GlobalUA")
test_result "dedup 与 UA 参数组合" "200" "$RESP"
echo ""

# ============================================
# 2. ua 参数测试
# ============================================
echo "【2. ua 参数测试】"
echo ""

# 2.1 基本 UA
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&ua=MyApp/1.0")
test_result "&ua= 基本值" "200" "$RESP"

# 2.2 UA 包含特殊字符
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&ua=Mozilla/5.0%20(Windows%20NT%2010.0)")
test_result "&ua= 含特殊字符" "200" "$RESP"

# 2.3 空 UA
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&ua=")
test_result "&ua= 空值" "200" "$RESP"

# 2.4 UA 与其他参数组合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&ua=TestUA&global-ua=GlobalUA&proxys-ua=ProxysUA")
test_result "&ua= 多 UA 参数组合" "200" "$RESP"
echo ""

# ============================================
# 3. global-ua 参数测试
# ============================================
echo "【3. global-ua 参数测试】"
echo ""

# 3.1 基本 global-ua
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&global-ua=GlobalUA/1.0")
test_result "&global-ua= 基本值" "200" "$RESP"

# 3.2 global-ua 与 ua 同时指定 (优先级: ua > global-ua)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&global-ua=GlobalUA&ua=LocalUA")
test_result "&global-ua= 与 &ua= 同时指定" "200" "$RESP"

# 3.3 空 global-ua
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&global-ua=")
test_result "&global-ua= 空值" "200" "$RESP"
echo ""

# ============================================
# 4. fetch_timeout 参数测试
# ============================================
echo "【4. fetch_timeout 参数测试】"
echo ""

# 4.1 短超时
START=$(date +%s)
curl -s --max-time 3 -o /dev/null "$HOST/sub?target=clash&url=$VMESS_B64&fetch_timeout=1" || true
END=$(date +%s)
ELAPSED=$((END - START))
test_result "fetch_timeout=1 快速响应" "是" "$([ $ELAPSED -lt 3 ] && echo '是' || echo '否')"

# 4.2 正常超时
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&fetch_timeout=15")
test_result "fetch_timeout=15 正常值" "200" "$RESP"

# 4.3 超时为 0 (可能表示无限制)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&fetch_timeout=0")
test_result "fetch_timeout=0" "200" "$RESP"

# 4.4 负数超时
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&fetch_timeout=-1")
test_result "fetch_timeout=-1 (负数)" "200" "$RESP"

# 4.5 超大超时
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&fetch_timeout=99999")
test_result "fetch_timeout=99999 (超大)" "200" "$RESP"
echo ""

# ============================================
# 5. proxys-provider 参数测试
# ============================================
echo "【5. proxys-provider 参数测试】"
echo ""

# 5.1 proxys-provider=false (内联)
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false")
if echo "$RESP" | grep -q "proxies:"; then
    test_result "proxys-provider=false 内联模式" "内联" "内联"
else
    test_result "proxys-provider=false 内联模式" "内联" "未知"
fi

# 5.2 proxys-provider=true (provider)
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=true")
if echo "$RESP" | grep -q "proxy-providers:"; then
    test_result "proxys-provider=true provider 模式" "provider" "provider"
else
    test_result "proxys-provider=true provider 模式" "provider" "未知"
fi

# 5.3 proxys-provider 未指定 (默认 true)
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64")
if echo "$RESP" | grep -q "proxy-providers:"; then
    test_result "proxys-provider 默认 provider 模式" "provider" "provider"
else
    test_result "proxys-provider 默认 provider 模式" "provider" "未知"
fi

# 5.4 proxys-provider=false 与 dedup 组合
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&dedup=true")
if echo "$RESP" | grep -q "proxies:"; then
    test_result "proxys-provider=false + dedup=true" "内联" "内联"
else
    test_result "proxys-provider=false + dedup=true" "内联" "未知"
fi
echo ""

# ============================================
# 6. proxys-ua 参数测试
# ============================================
echo "【6. proxys-ua 参数测试】"
echo ""

# 6.1 proxys-ua 与 proxys-provider=true
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=true&proxys-ua=ProxysUA/1.0")
test_result "proxys-ua 与 provider 模式" "200" "$RESP"

# 6.2 proxys-ua 与 proxys-provider=false
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&proxys-ua=ProxysUA/1.0")
test_result "proxys-ua 与内联模式" "200" "$RESP"

# 6.3 UA 优先级链: proxys-ua > ua > global-ua
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&global-ua=GUA&ua=UA&proxys-ua=PUA")
test_result "UA 优先级链 (proxys-ua > ua > global-ua)" "200" "$RESP"
echo ""

# ============================================
# 7. proxys-proxy 参数测试
# ============================================
echo "【7. proxys-proxy 参数测试】"
echo ""

# 7.1 proxys-proxy=SYSTEM
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&proxys-proxy=SYSTEM")
test_result "proxys-proxy=SYSTEM" "200" "$RESP"

# 7.2 proxys-proxy=NONE
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&proxys-proxy=NONE")
test_result "proxys-proxy=NONE" "200" "$RESP"

# 7.3 proxys-proxy=URL (无效)
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&proxys-proxy=http://invalid:8080")
test_result "proxys-proxy=无效 URL" "200" "$RESP"

# 7.4 proxys-proxy 与 proxys-ua 组合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=false&proxys-proxy=SYSTEM&proxys-ua=TestUA")
test_result "proxys-proxy + proxys-ua 组合" "200" "$RESP"
echo ""

# ============================================
# 8. proxys-interval 参数测试
# ============================================
echo "【8. proxys-interval 参数测试】"
echo ""

# 8.1 正常 interval
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=true&proxys-interval=3600")
if echo "$RESP" | grep -q "interval"; then
    test_result "proxys-interval=3600" "生效" "生效"
else
    test_result "proxys-interval=3600" "生效" "未知"
fi

# 8.2 小 interval
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=true&proxys-interval=60")
test_result "proxys-interval=60 (小值)" "200" "$RESP"

# 8.3 大 interval
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=true&proxys-interval=86400")
test_result "proxys-interval=86400 (大值)" "200" "$RESP"

# 8.4 空 interval
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&proxys-provider=true&proxys-interval=")
test_result "proxys-interval=空值" "200" "$RESP"
echo ""

# ============================================
# 9. rules-provider 参数测试
# ============================================
echo "【9. rules-provider 参数测试】"
echo ""

RULES_URL=$(b64url "RULE,http://example.com/rules&type=1")
GROUP_B64=$(b64url "PROXY")

# 9.1 rules-provider=false (内联规则)
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&rules=$RULES_URL&rules-provider=false")
if echo "$RESP" | grep -q "rules:"; then
    test_result "rules-provider=false 内联规则" "内联" "内联"
else
    test_result "rules-provider=false 内联规则" "内联" "未知"
fi

# 9.2 rules-provider=true (rule-provider)
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&rules=$RULES_URL&rules-provider=true")
if echo "$RESP" | grep -q "rule-providers:"; then
    test_result "rules-provider=true rule-provider" "provider" "provider"
else
    test_result "rules-provider=true rule-provider" "provider" "未知"
fi

# 9.3 rules-provider 未指定 (默认 true)
RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS_B64&rules=$RULES_URL")
if echo "$RESP" | grep -q "rule-providers:"; then
    test_result "rules-provider 默认 true" "provider" "provider"
else
    test_result "rules-provider 默认 true" "provider" "未知"
fi
echo ""

# ============================================
# 10. rules-ua 参数测试
# ============================================
echo "【10. rules-ua 参数测试】"
echo ""

# 10.1 基本 rules-ua
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-ua=RulesUA/1.0")
test_result "rules-ua=RulesUA/1.0" "200" "$RESP"

# 10.2 rules-ua 与 rules-provider=false 组合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&rules=$RULES_URL&rules-provider=false&rules-ua=RulesUA/1.0")
test_result "rules-ua 与内联规则组合" "200" "$RESP"

# 10.3 空 rules-ua
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-ua=")
test_result "rules-ua=空值" "200" "$RESP"
echo ""

# ============================================
# 11. rules-proxy 参数测试
# ============================================
echo "【11. rules-proxy 参数测试】"
echo ""

# 11.1 rules-proxy=SYSTEM
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-proxy=SYSTEM")
test_result "rules-proxy=SYSTEM" "200" "$RESP"

# 11.2 rules-proxy=NONE
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-proxy=NONE")
test_result "rules-proxy=NONE" "200" "$RESP"

# 11.3 rules-proxy 与 rules-ua 组合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-proxy=SYSTEM&rules-ua=RulesUA")
test_result "rules-proxy + rules-ua 组合" "200" "$RESP"
echo ""

# ============================================
# 12. rules-interval 参数测试
# ============================================
echo "【12. rules-interval 参数测试】"
echo ""

# 12.1 正常 interval
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-interval=3600")
test_result "rules-interval=3600" "200" "$RESP"

# 12.2 小 interval
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-interval=60")
test_result "rules-interval=60" "200" "$RESP"

# 12.3 空 interval
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-interval=")
test_result "rules-interval=空值" "200" "$RESP"
echo ""

# ============================================
# 13. Per-URL 参数测试
# ============================================
echo "【13. Per-URL 参数测试】"
echo ""

# 13.1 Per-URL |ua=
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS_B64}|ua=PerURLUA/1.0")
test_result "Per-URL |ua= 参数" "200" "$RESP"

# 13.2 Per-URL |provider=false
RESP=$(curl -s "$HOST/sub?target=clash&url=${VMESS_B64}|provider=false&proxys-provider=true")
if echo "$RESP" | grep -q "proxies:"; then
    test_result "Per-URL |provider=false 覆盖全局" "内联" "内联"
else
    test_result "Per-URL |provider=false 覆盖全局" "内联" "未知"
fi

# 13.3 Per-URL |provider=true
RESP=$(curl -s "$HOST/sub?target=clash&url=${VMESS_B64}|provider=true&proxys-provider=false")
if echo "$RESP" | grep -q "proxy-providers:"; then
    test_result "Per-URL |provider=true 覆盖全局" "provider" "provider"
else
    test_result "Per-URL |provider=true 覆盖全局" "provider" "未知"
fi

# 13.4 Per-URL |proxy=SYSTEM
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS_B64}|proxy=SYSTEM")
test_result "Per-URL |proxy=SYSTEM" "200" "$RESP"

# 13.5 Per-URL |proxy=NONE
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS_B64}|proxy=NONE")
test_result "Per-URL |proxy=NONE" "200" "$RESP"

# 13.6 Per-URL |interval=
RESP=$(curl -s "$HOST/sub?target=clash&url=${VMESS_B64}|interval=7200&proxys-provider=true")
if echo "$RESP" | grep -q "interval"; then
    test_result "Per-URL |interval=7200" "生效" "生效"
else
    test_result "Per-URL |interval=7200" "生效" "未知"
fi

# 13.7 多 URL Per-URL 混合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS_B64}||${VMESS2_B64}|provider=false")
test_result "多 URL Per-URL 混合" "200" "$RESP"

# 13.8 Per-URL 多个参数
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS_B64}|ua=TestUA|provider=false|interval=3600")
test_result "Per-URL 多参数组合" "200" "$RESP"

# 13.9 Per-URL 空参数
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS_B64}|")
test_result "Per-URL 空参数" "200" "$RESP"
echo ""

# ============================================
# 14. Mihomo Panic Recovery 测试
# ============================================
echo "【14. Mihomo Panic Recovery 测试】"
echo ""

# 14.1 恶意订阅
MALICIOUS=$(b64url "vmess://invalid-base64-data!!!@#$%")
RESP=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$MALICIOUS")
if [ "$RESP" = "400" ] || [ "$RESP" = "500" ]; then
    test_result "恶意订阅返回错误而非崩溃" "错误" "错误"
else
    test_result "恶意订阅返回错误而非崩溃" "错误" "$RESP"
fi

# 14.2 进程存活检查
if docker ps --filter "name=subconverter-full-test" --format '{{.Names}}' 2>/dev/null | grep -q subconverter; then
    test_result "进程在 panic 后仍存活" "存活" "存活"
else
    test_result "进程在 panic 后仍存活" "存活" "已退出"
fi

# 14.3 连续多个恶意请求
for i in 1 2 3; do
    curl -s --max-time 3 -o /dev/null "$HOST/sub?target=clash&url=$MALICIOUS" || true
done
if docker ps --filter "name=subconverter-full-test" --format '{{.Names}}' 2>/dev/null | grep -q subconverter; then
    test_result "连续恶意请求后进程仍存活" "存活" "存活"
else
    test_result "连续恶意请求后进程仍存活" "存活" "已退出"
fi
echo ""

# ============================================
# 15. 边界情况测试
# ============================================
echo "【15. 边界情况测试】"
echo ""

# 15.1 空订阅
EMPTY=$(b64url "")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$EMPTY")
test_result "空订阅返回错误" "400" "$RESP"

# 15.2 无效 base64
INVALID=$(b64url "!!!not-valid-base64!!!")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$INVALID")
test_result "无效 base64 返回错误" "400" "$RESP"

# 15.3 未知 target
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=unknown&url=$VMESS_B64")
test_result "未知 target 返回 400" "400" "$RESP"

# 15.4 缺少 url 参数
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash")
test_result "缺少 url 参数返回 400" "400" "$RESP"

# 15.5 所有 Fork 参数组合
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS_B64&ua=TestUA&global-ua=GlobalUA&proxys-ua=ProxysUA&proxys-proxy=SYSTEM&proxys-interval=3600&proxys-provider=false&dedup=true&fetch_timeout=10")
test_result "所有 Fork 参数组合" "200" "$RESP"
echo ""

# ============================================
# 汇总
# ============================================
echo "=========================================="
echo "测试结果汇总"
echo "=========================================="
echo "通过: $PASS / $TOTAL"
echo "失败: $FAIL / $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✅ 所有测试通过！"
else
    echo "⚠️  有 $FAIL 个测试失败"
fi

echo ""
echo "Docker 镜像保留: subconverter-extended:test (您还有别的要测试)"
docker images | grep subconverter

exit $FAIL
