#!/bin/bash
# SubConverter-Extended 完整功能测试脚本
HOST="http://localhost:25500"
PASS=0
FAIL=0
TOTAL=0

echo "=========================================="
echo "SubConverter-Extended 完整功能测试"
echo "=========================================="
echo ""

# 辅助函数：URL-safe base64 编码（正确版）
b64url() {
    # $1 是原始字符串，不是已经 base64 过的
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

# 测试节点（原始字符串，不是 base64）
VMESS_RAW="vmess://test@test.example.com:443?type=tcp&security=tls#TestNode"
VMESS=$(b64url "$VMESS_RAW")
echo "  测试节点已准备"
echo ""

# ============================================
# 1. Origin 基本功能
# ============================================
echo "【1. Origin 基本功能测试】"
echo ""

RESP=$(curl -s "$HOST/version" | head -1)
if echo "$RESP" | grep -q "SubConverter"; then
    test_result "/version 端点" "正常" "正常"
else
    test_result "/version 端点" "正常" "异常"
fi

RESP=$(curl -s "$HOST/inspect" | head -1)
if echo "$RESP" | grep -q "inspect\|Inspect"; then
    test_result "/inspect 端点" "正常" "正常"
else
    test_result "/inspect 端点" "正常" "异常"
fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/dashboard")
test_result "Dashboard 访问" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&proxys-provider=false")
test_result "vmess 节点转换 (clash)" "200" "$RESP"

VLESS_RAW="vless://test@test.example.com:443?type=tcp&security=tls#TestVLESS"
VLESS=$(b64url "$VLESS_RAW")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VLESS&proxys-provider=false")
test_result "vless 节点转换 (clash)" "200" "$RESP"

TROJAN_RAW="trojan://testpass@test.example.com:443#TestTrojan"
TROJAN=$(b64url "$TROJAN_RAW")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$TROJAN&proxys-provider=false")
test_result "trojan 节点转换 (clash)" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=sing-box&url=$VMESS&proxys-provider=false")
test_result "SingBox 目标" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=stash&url=$VMESS")
test_result "Stash 目标" "200" "$RESP"
echo ""

# ============================================
# 2. Origin 新功能
# ============================================
echo "【2. Origin 新功能测试】"
echo ""

MIERU_RAW="mieru://test.example.com:443?security=aes-128-gcm&plugin=..."
MIERU=$(b64url "$MIERU_RAW")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$MIERU&proxys-provider=false")
test_result "Mieru 协议支持" "200" "$RESP"

AGE_RAW="age://encrypted-data-example"
AGE=$(b64url "$AGE_RAW")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$AGE")
test_result "Age 加密订阅处理" "非500" "$RESP"

RESP=$(curl -s -H "X-Forwarded-Prefix: /subconverter" "$HOST/dashboard" | grep -o 'href="[^"]*"' | head -5)
if echo "$RESP" | grep -qE '\./|dashboard/'; then
    test_result "Dashboard 相对路径（子路径部署）" "相对路径" "相对路径"
else
    test_result "Dashboard 相对路径（子路径部署）" "相对路径" "绝对路径"
fi
echo ""

# ============================================
# 3. Fork 独有功能：dedup
# ============================================
echo "【3. Fork 独有功能：规则去重 (dedup)】"
echo ""

cat > /tmp/test_dedup.yaml << 'EOF'
proxies:
  - {name: "Test-1", type: vmess, server: 1.2.3.4, port: 1234, uuid: "12345678-1234-1234-1234-123456789abc", alterId: 0, cipher: auto}
  - {name: "Test-2", type: vmess, server: 1.2.3.4, port: 1235, uuid: "12345678-1234-1234-1234-123456789abc", alterId: 0, cipher: auto}
proxy-groups:
  - {name: "PROXY", type: select, proxies: ["Test-1", "Test-2"]}
rules:
  - "DOMAIN,dup1.com,PROXY"
  - "DOMAIN,dup1.com,PROXY"
  - "DOMAIN,unique1.com,DIRECT"
  - "MATCH,PROXY"
EOF

curl -s -X POST -d @/tmp/test_dedup.yaml "$HOST/sub?target=clash&dedup=true" > /tmp/dedup_true.yaml
RULES_DEDUP=$(grep -c "^\s*- " /tmp/dedup_true.yaml || echo "0")

curl -s -X POST -d @/tmp/test_dedup.yaml "$HOST/sub?target=clash&dedup=false" > /tmp/dedup_false.yaml
RULES_NO_DEDUP=$(grep -c "^\s*- " /tmp/dedup_false.yaml || echo "0")

test_result "内联规则 dedup=true 应去重到 3 条" "3" "$RULES_DEDUP"
test_result "内联规则 dedup=false 应保留 4 条" "4" "$RULES_NO_DEDUP"

curl -s -X POST -d @/tmp/test_dedup.yaml "$HOST/sub?target=clash" > /tmp/dedup_default.yaml
RULES_DEFAULT=$(grep -c "^\s*- " /tmp/dedup_default.yaml || echo "0")
test_result "内联规则 dedup 默认应去重" "3" "$RULES_DEFAULT"
echo ""

# ============================================
# 4. Fork 独有功能：UA 参数
# ============================================
echo "【4. Fork 独有功能：UA 参数测试】"
echo ""

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&ua=TestUA/2.0")
test_result "&ua= 参数" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&global-ua=GlobalUA/1.0")
test_result "&global-ua= 参数" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&proxys-ua=ProxysUA/1.0")
test_result "&proxys-ua= 参数" "200" "$RESP"
echo ""

# ============================================
# 5. Fork 独有功能：fetch_timeout
# ============================================
echo "【5. Fork 独有功能：fetch_timeout 测试】"
echo ""

START=$(date +%s)
curl -s --max-time 5 -o /dev/null "$HOST/sub?target=clash&url=$VMESS&fetch_timeout=1" || true
END=$(date +%s)
ELAPSED=$((END - START))
test_result "fetch_timeout=1 快速响应（<5秒）" "是" "$([ $ELAPSED -lt 5 ] && echo '是' || echo "否(${ELAPSED}s)")"
echo ""

# ============================================
# 6. Fork 独有功能：proxys-provider
# ============================================
echo "【6. Fork 独有功能：proxys-provider 测试】"
echo ""

RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS&proxys-provider=false")
if echo "$RESP" | grep -q "proxies:"; then
    test_result "proxys-provider=false 内联模式" "内联" "内联"
else
    test_result "proxys-provider=false 内联模式" "内联" "未知"
fi

RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS&proxys-provider=true")
if echo "$RESP" | grep -q "proxy-providers:"; then
    test_result "proxys-provider=true provider 模式" "provider" "provider"
else
    test_result "proxys-provider=true provider 模式" "provider" "未知"
fi
echo ""

# ============================================
# 7. Fork 独有功能：proxys-proxy
# ============================================
echo "【7. Fork 独有功能：proxys-proxy 测试】"
echo ""

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&proxys-proxy=SYSTEM")
test_result "proxys-proxy=SYSTEM" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&proxys-proxy=NONE")
test_result "proxys-proxy=NONE" "200" "$RESP"
echo ""

# ============================================
# 8. Fork 独有功能：proxys-interval
# ============================================
echo "【8. Fork 独有功能：proxys-interval 测试】"
echo ""

RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS&proxys-interval=3600")
if echo "$RESP" | grep -q "interval"; then
    test_result "proxys-interval=3600 参数生效" "生效" "生效"
else
    test_result "proxys-interval=3600 参数生效" "生效" "未知"
fi
echo ""

# ============================================
# 9. Fork 独有功能：rules-provider
# ============================================
echo "【9. Fork 独有功能：rules-provider 测试】"
echo ""

RULES_URL=$(b64url "RULE,http://example.com/rules&type=1")
GROUP_B64=$(b64url "PROXY")

RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS&rules=$RULES_URL&rules-provider=false")
if echo "$RESP" | grep -q "rules:"; then
    test_result "rules-provider=false 内联规则" "内联" "内联"
else
    test_result "rules-provider=false 内联规则" "内联" "未知"
fi

RESP=$(curl -s "$HOST/sub?target=clash&url=$VMESS&rules=$RULES_URL&rules-provider=true")
if echo "$RESP" | grep -q "rule-providers:"; then
    test_result "rules-provider=true rule-provider 模式" "provider" "provider"
else
    test_result "rules-provider=true rule-provider 模式" "provider" "未知"
fi
echo ""

# ============================================
# 10. Fork 独有功能：rules-ua
# ============================================
echo "【10. Fork 独有功能：rules-ua 测试】"
echo ""

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-ua=RulesUA/1.0")
test_result "rules-ua=RulesUA/1.0 参数" "200" "$RESP"
echo ""

# ============================================
# 11. Fork 独有功能：rules-proxy
# ============================================
echo "【11. Fork 独有功能：rules-proxy 测试】"
echo ""

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-proxy=SYSTEM")
test_result "rules-proxy=SYSTEM 参数" "200" "$RESP"
echo ""

# ============================================
# 12. Fork 独有功能：rules-interval
# ============================================
echo "【12. Fork 独有功能：rules-interval 测试】"
echo ""

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/getruleset?url=$RULES_URL&type=1&group=$GROUP_B64&rules-interval=3600")
test_result "rules-interval=3600 参数" "200" "$RESP"
echo ""

# ============================================
# 13. Fork 独有功能：Per-URL 参数
# ============================================
echo "【13. Fork 独有功能：Per-URL 参数测试】"
echo ""

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS}|ua=PerURLUA/1.0")
test_result "Per-URL |ua= 参数" "200" "$RESP"

RESP=$(curl -s "$HOST/sub?target=clash&url=${VMESS}|provider=false&proxys-provider=true")
if echo "$RESP" | grep -q "proxies:"; then
    test_result "Per-URL |provider=false 覆盖全局" "内联" "内联"
else
    test_result "Per-URL |provider=false 覆盖全局" "内联" "未知"
fi

RESP=$(curl -s "$HOST/sub?target=clash&url=${VMESS}|provider=true&proxys-provider=false")
if echo "$RESP" | grep -q "proxy-providers:"; then
    test_result "Per-URL |provider=true 覆盖全局" "provider" "provider"
else
    test_result "Per-URL |provider=true 覆盖全局" "provider" "未知"
fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS}|proxy=SYSTEM")
test_result "Per-URL |proxy=SYSTEM" "200" "$RESP"

RESP=$(curl -s "$HOST/sub?target=clash&url=${VMESS}|interval=7200")
if echo "$RESP" | grep -q "interval"; then
    test_result "Per-URL |interval=7200" "生效" "生效"
else
    test_result "Per-URL |interval=7200" "生效" "未知"
fi

VMESS2_RAW="vmess://test2@test2.example.com:444?type=tcp&security=tls#TestNode2"
VMESS2=$(b64url "$VMESS2_RAW")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=${VMESS}||${VMESS2}|provider=false")
test_result "多 URL Per-URL 混合" "200" "$RESP"
echo ""

# ============================================
# 14. Fork 独有功能：Mihomo Panic Recovery
# ============================================
echo "【14. Fork 独有功能：Mihomo Panic Recovery 测试】"
echo ""

MALICIOUS=$(b64url "vmess://invalid-base64-data!!!@#$%")
RESP=$(curl -s --max-time 5 "$HOST/sub?target=clash&url=$MALICIOUS")
if echo "$RESP" | grep -q "error\|Error\|Invalid\|no valid"; then
    test_result "恶意订阅返回错误而非崩溃" "错误" "错误"
else
    test_result "恶意订阅返回错误而非崩溃" "错误" "未知"
fi

if docker ps --filter "name=subconverter-full-test" --format '{{.Names}}' 2>/dev/null | grep -q subconverter; then
    test_result "进程在 panic 后仍存活" "存活" "存活"
else
    test_result "进程在 panic 后仍存活" "存活" "已退出"
fi
echo ""

# ============================================
# 15. 边界情况测试
# ============================================
echo "【15. 边界情况测试】"
echo ""

EMPTY=$(b64url "")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$EMPTY")
test_result "空订阅返回错误" "400" "$RESP"

INVALID=$(b64url "!!!not-valid-base64!!!")
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$INVALID")
test_result "无效 base64 返回错误" "400" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash&url=$VMESS&ua=TestUA&global-ua=GlobalUA&proxys-ua=ProxysUA&proxys-provider=false&dedup=true&fetch_timeout=10")
test_result "多参数组合不崩溃" "200" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=unknown&url=$VMESS")
test_result "未知 target 返回 400" "400" "$RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$HOST/sub?target=clash")
test_result "缺少 url 参数返回 400" "400" "$RESP"
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

# 清理
rm -f /tmp/test_dedup.yaml /tmp/dedup_*.yaml

echo ""
echo "Docker 镜像保留: subconverter-extended:test (您还有别的要测试)"
docker images | grep subconverter

exit $FAIL
