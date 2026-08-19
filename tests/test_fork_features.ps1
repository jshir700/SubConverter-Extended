# SubConverter-Extended 完整功能测试脚本 (PowerShell)
# 测试 Fork 独有功能 + Origin 功能 + 边界情况

$HostAddr = "http://localhost:25500"
$FakePort = 18083
$Pass = 0
$Fail = 0
$Total = 0

Write-Host "=========================================="
Write-Host "SubConverter-Extended 完整功能测试"
Write-Host "=========================================="
Write-Host ""

function Test-Result {
    param($Name, $Expected, $Actual)
    $Total++
    if ($Expected -eq $Actual) {
        Write-Host "  ✅ PASS: $Name"
        $script:Pass++
    } else {
        Write-Host "  ❌ FAIL: $Name"
        Write-Host "    期望: [$Expected] 实际: [$Actual]"
        $script:Fail++
    }
}

function Base64Url-Encode {
    param([string]$Input)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Input)
    $b64 = [Convert]::ToBase64String($bytes)
    return $b64.Replace('+', '-').Replace('/', '_').Replace('=', '')
}

# ============================================
# 启动 Fake Server (PowerShell)
# ============================================
Write-Host "【准备测试环境】"
Write-Host ""

$FakeServerScript = @'
param([int]$Port = 18083)
Add-Type -AssemblyName System.Net.Http
$rulesets = @{
    "/surge" = "DOMAIN,dup1.com,PROXY`nDOMAIN,dup1.com,DIRECT`nDOMAIN,unique1.com,PROXY`nDOMAIN-SUFFIX,dup2.net,PROXY`nDOMAIN-SUFFIX,dup2.net,PROXY`n"
    "/quanx" = "DOMAIN,dup1.com,PROXY`nDOMAIN,dup1.com,DIRECT`nDOMAIN,unique1.com,PROXY`nIP-CIDR,10.0.0.0/8,DIRECT`nIP-CIDR,10.0.0.0/8,PROXY`n"
    "/clash-domain" = "DOMAIN,dup1.com`nDOMAIN,dup1.com`nDOMAIN-SUFFIX,dup2.net`nDOMAIN-SUFFIX,dup2.net`nDOMAIN,unique1.com`nDOMAIN-SUFFIX,unique2.org`n"
    "/clash-ipcidr" = "IP-CIDR,10.0.0.0/8`nIP-CIDR,10.0.0.0/8`nIP-CIDR,10.0.0.0/8,no-resolve`nIP-CIDR6,2001:db8::/32`nIP-CIDR,172.16.0.0/12`n"
    "/clash-classical" = "DOMAIN,dup1.com,PROXY`nDOMAIN,dup1.com,DIRECT`nDOMAIN-SUFFIX,dup2.net,PROXY`nDOMAIN-SUFFIX,dup2.net,PROXY`nIP-CIDR,10.0.0.0/8,PROXY,no-resolve`nIP-CIDR,10.0.0.0/8,DIRECT,no-resolve`nDOMAIN-KEYWORD,ads,REJECT`nDOMAIN-KEYWORD,ads,PROXY`nMATCH,DIRECT`n"
    "/surge-domainset" = "DOMAIN,dup1.com`nDOMAIN,dup1.com`nDOMAIN-SUFFIX,dup2.net`nDOMAIN-SUFFIX,dup2.net`nDOMAIN,unique1.com`n"
}
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Fake server on port $Port"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $resp = $ctx.Response
    $path = $req.Url.AbsolutePath
    if ($path -eq "/ua-echo") {
        $ua = $req.Headers.Get("User-Agent")
        $body = "UA:$ua`n"
    } elseif ($path -eq "/slow") {
        $delay = [int]($req.Url.Query.Split('&') | ForEach-Object { $_.Split('=')[1] })
        Start-Sleep -Seconds $delay
        $body = "OK after ${delay}s`n"
    } elseif ($rulesets.ContainsKey($path)) {
        $body = $rulesets[$path]
    } else {
        $resp.StatusCode = 404
        $body = ""
    }
    if ($body) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $resp.ContentType = "text/plain"
        $resp.ContentLength64 = $bytes.Length
        $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    $resp.Close()
}
'@

$FakeServer = Start-Job -ScriptBlock [scriptblock]::Create($FakeServerScript)
Start-Sleep -Seconds 1
Write-Host "  Fake server started on port $FakePort"
Write-Host ""

# ============================================
# 1. 规则去重测试 (dedup)
# ============================================
Write-Host "【1. 规则去重测试 (dedup)】"
Write-Host ""

# 测试 /getruleset 各类型去重
$tests = @(
    @{ Type=1; Path="/surge"; ExpectedDedup=3; ExpectedNoDedup=5 },
    @{ Type=2; Path="/quanx"; ExpectedDedup=3; ExpectedNoDedup=5 },
    @{ Type=3; Path="/clash-domain"; ExpectedDedup=4; ExpectedNoDedup=6 },
    @{ Type=4; Path="/clash-ipcidr"; ExpectedDedup=4; ExpectedNoDedup=5 },
    @{ Type=5; Path="/surge-domainset"; ExpectedDedup=3; ExpectedNoDedup=5 },
    @{ Type=6; Path="/clash-classical"; ExpectedDedup=4; ExpectedNoDedup=7 }
)

foreach ($t in $tests) {
    $urlB64 = Base64Url-Encode "RULE,http://127.0.0.1:$($FakePort)$($t.Path)&type=$($t.Type)"
    $groupB64 = Base64Url-Encode "PROXY"

    # dedup=true
    $respDedup = Invoke-RestMethod -Uri "$HostAddr/getruleset?url=$urlB64&type=$($t.Type)&group=$groupB64&dedup=true" -ErrorAction SilentlyContinue
    # dedup=false
    $respNoDedup = Invoke-RestMethod -Uri "$HostAddr/getruleset?url=$urlB64&type=$($t.Type)&group=$groupB64&dedup=false" -ErrorAction SilentlyContinue

    # Count rules (simplified)
    $countDedup = ($respDedup | Out-String).Split("`n").Where{$_ -match "DOMAIN|IP-CIDR"}.Count
    $countNoDedup = ($respNoDedup | Out-String).Split("`n").Where{$_ -match "DOMAIN|IP-CIDR"}.Count

    Test-Result "type=$($t.Type) dedup=true" "$($t.ExpectedDedup)" "$countDedup"
    Test-Result "type=$($t.Type) dedup=false" "$($t.ExpectedNoDedup)" "$countNoDedup"
}
Write-Host ""

# ============================================
# 2. UA 参数测试
# ============================================
Write-Host "【2. UA 参数测试】"
Write-Host ""

$vmess = Base64Url-Encode "vmess://eyJ2IjoiMiIsInBzIjoiVGVzdCIsImFkZCI6IjEuMi4zLjQiLCJwb3J0IjoiMTIzNCIsImlkIjoiMTIzNDU2NzgtaWRlbnRpZmllciIsImFsaXRJZCI6MCwiY3l6ZXIiOiJhdXRvIn0="

# &ua= 参数
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&ua=TestUA/2.0" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "&ua= 参数不崩溃" "200" $resp.StatusCode
} catch {
    Test-Result "&ua= 参数不崩溃" "200" "error"
}

# &global-ua= 参数
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&global-ua=GlobalUA/1.0" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "&global-ua= 参数不崩溃" "200" $resp.StatusCode
} catch {
    Test-Result "&global-ua= 参数不崩溃" "200" "error"
}

# &proxys-ua= 参数
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&proxys-ua=ProxysUA/1.0" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "&proxys-ua= 参数不崩溃" "200" $resp.StatusCode
} catch {
    Test-Result "&proxys-ua= 参数不崩溃" "200" "error"
}
Write-Host ""

# ============================================
# 3. fetch_timeout 测试
# ============================================
Write-Host "【3. fetch_timeout 参数测试】"
Write-Host ""

# 短超时测试
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&fetch_timeout=1" -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
} catch {}
$sw.Stop()
Test-Result "fetch_timeout=1 快速响应" "是" "$($sw.ElapsedMilliseconds -lt 5000)"
Write-Host ""

# ============================================
# 4. proxys-provider 参数测试
# ============================================
Write-Host "【4. proxys-provider 参数测试】"
Write-Host ""

# proxys-provider=false (内联)
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&proxys-provider=false" -TimeoutSec 5 -ErrorAction Stop
    $body = $resp.Content
    if ($body -match "proxies:") {
        Test-Result "proxys-provider=false 内联模式" "内联" "内联"
    } else {
        Test-Result "proxys-provider=false 内联模式" "内联" "未知"
    }
} catch {
    Test-Result "proxys-provider=false 内联模式" "内联" "错误"
}

# proxys-provider=true (provider)
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&proxys-provider=true" -TimeoutSec 5 -ErrorAction Stop
    $body = $resp.Content
    if ($body -match "proxy-providers:") {
        Test-Result "proxys-provider=true provider 模式" "provider" "provider"
    } else {
        Test-Result "proxys-provider=true provider 模式" "provider" "未知"
    }
} catch {
    Test-Result "proxys-provider=true provider 模式" "provider" "错误"
}
Write-Host ""

# ============================================
# 5. Per-URL 参数测试
# ============================================
Write-Host "【5. Per-URL 参数测试】"
Write-Host ""

# Per-URL |ua=
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess|ua=PerURLUA/1.0" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "Per-URL |ua= 参数" "200" $resp.StatusCode
} catch {
    Test-Result "Per-URL |ua= 参数" "200" "error"
}

# Per-URL |provider=false
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess|provider=false&proxys-provider=true" -TimeoutSec 5 -ErrorAction Stop
    $body = $resp.Content
    if ($body -match "proxies:") {
        Test-Result "Per-URL |provider=false 覆盖全局" "内联" "内联"
    } else {
        Test-Result "Per-URL |provider=false 覆盖全局" "内联" "未知"
    }
} catch {
    Test-Result "Per-URL |provider=false 覆盖全局" "内联" "错误"
}

# Per-URL |proxy=SYSTEM
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess|proxy=SYSTEM" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "Per-URL |proxy=SYSTEM" "200" $resp.StatusCode
} catch {
    Test-Result "Per-URL |proxy=SYSTEM" "200" "error"
}

# Per-URL |interval=
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess|interval=7200" -TimeoutSec 5 -ErrorAction Stop
    $body = $resp.Content
    if ($body -match "interval") {
        Test-Result "Per-URL |interval=7200" "生效" "生效"
    } else {
        Test-Result "Per-URL |interval=7200" "生效" "未知"
    }
} catch {
    Test-Result "Per-URL |interval=7200" "生效" "错误"
}
Write-Host ""

# ============================================
# 6. 内联规则去重测试
# ============================================
Write-Host "【6. 内联规则去重测试】"
Write-Host ""

$testConfig = @'
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
'@

try {
    $respTrue = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&dedup=true" -Method POST -Body $testConfig -TimeoutSec 5 -ErrorAction Stop
    $rulesTrue = ($respTrue.Content -split "`n").Where{$_ -match "^\s*- "}.Count
    Test-Result "内联规则 dedup=true 应去重到 3 条" "3" $rulesTrue
} catch {
    Test-Result "内联规则 dedup=true 应去重到 3 条" "3" "error"
}

try {
    $respFalse = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&dedup=false" -Method POST -Body $testConfig -TimeoutSec 5 -ErrorAction Stop
    $rulesFalse = ($respFalse.Content -split "`n").Where{$_ -match "^\s*- "}.Count
    Test-Result "内联规则 dedup=false 应保留 4 条" "4" $rulesFalse
} catch {
    Test-Result "内联规则 dedup=false 应保留 4 条" "4" "error"
}
Write-Host ""

# ============================================
# 7. 反向代理子路径测试
# ============================================
Write-Host "【7. 反向代理子路径测试】"
Write-Host ""

try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/dashboard" -Headers @{"X-Forwarded-Prefix"="/subconverter"} -TimeoutSec 5 -ErrorAction Stop
    $body = $resp.Content
    if ($body -match 'href="[^"]*\.\/|href="dashboard\/') {
        Test-Result "Dashboard 相对路径（支持子路径部署）" "相对路径" "相对路径"
    } else {
        Test-Result "Dashboard 相对路径（支持子路径部署）" "相对路径" "绝对路径"
    }
} catch {
    Test-Result "Dashboard 相对路径（支持子路径部署）" "相对路径" "错误"
}
Write-Host ""

# ============================================
# 8. Mihomo Panic Recovery 测试
# ============================================
Write-Host "【8. Mihomo Panic Recovery 测试】"
Write-Host ""

$malicious = Base64Url-Encode "vmess://invalid-base64!!!@#$%"
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$malicious" -TimeoutSec 5 -ErrorAction Stop
    $body = $resp.Content
    if ($body -match "error|Error|Invalid|no valid") {
        Test-Result "恶意订阅返回错误而非崩溃" "错误" "错误"
    } else {
        Test-Result "恶意订阅返回错误而非崩溃" "错误" "未知"
    }
} catch {
    Test-Result "恶意订阅返回错误而非崩溃" "错误" "错误"
}

# 检查进程是否存活
$container = docker ps --filter "name=subconverter-full-test" --format "{{.Names}}" 2>$null
if ($container -eq "subconverter-full-test") {
    Test-Result "进程在 panic 后仍存活" "存活" "存活"
} else {
    Test-Result "进程在 panic 后仍存活" "存活" "已退出"
}
Write-Host ""

# ============================================
# 9. Origin 基本功能测试
# ============================================
Write-Host "【9. Origin 基本功能测试】"
Write-Host ""

# /version
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/version" -TimeoutSec 5 -ErrorAction Stop
    if ($resp.Content -match "SubConverter") {
        Test-Result "/version 端点" "正常" "正常"
    } else {
        Test-Result "/version 端点" "正常" "异常"
    }
} catch {
    Test-Result "/version 端点" "正常" "错误"
}

# /inspect
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/inspect" -TimeoutSec 5 -ErrorAction Stop
    if ($resp.Content -match "inspect|Inspect") {
        Test-Result "/inspect 端点" "正常" "正常"
    } else {
        Test-Result "/inspect 端点" "正常" "异常"
    }
} catch {
    Test-Result "/inspect 端点" "正常" "错误"
}

# vmess 转换
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&proxys-provider=false" -TimeoutSec 5 -ErrorAction Stop
    if ($resp.Content -match "proxies:") {
        Test-Result "vmess 节点转换 (clash)" "正常" "正常"
    } else {
        Test-Result "vmess 节点转换 (clash)" "正常" "异常"
    }
} catch {
    Test-Result "vmess 节点转换 (clash)" "正常" "错误"
}

# vless 转换
$vless = Base64Url-Encode "vless://test@test.example.com:443?type=tcp&security=tls#TestVLESS"
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vless&proxys-provider=false" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "vless 节点转换 (clash)" "200" $resp.StatusCode
} catch {
    Test-Result "vless 节点转换 (clash)" "200" "error"
}

# trojan 转换
$trojan = Base64Url-Encode "trojan://testpass@test.example.com:443#TestTrojan"
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$trojan&proxys-provider=false" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "trojan 节点转换 (clash)" "200" $resp.StatusCode
} catch {
    Test-Result "trojan 节点转换 (clash)" "200" "error"
}
Write-Host ""

# ============================================
# 10. Origin 新功能测试
# ============================================
Write-Host "【10. Origin 新功能测试】"
Write-Host ""

# Mieru 协议
$mieru = Base64Url-Encode "mieru://test.example.com:443?security=aes-128-gcm&plugin=..."
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$mieru&proxys-provider=false" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "Mieru 协议支持" "200" $resp.StatusCode
} catch {
    Test-Result "Mieru 协议支持" "200" "error"
}

# Stash 配置
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=stash&url=$vmess" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "Stash 配置生成" "200" $resp.StatusCode
} catch {
    Test-Result "Stash 配置生成" "200" "error"
}

# Dashboard
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/dashboard" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "Dashboard 页面访问" "200" $resp.StatusCode
} catch {
    Test-Result "Dashboard 页面访问" "200" "error"
}

# SingBox
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=sing-box&url=$vmess&proxys-provider=false" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "SingBox 目标支持" "200" $resp.StatusCode
} catch {
    Test-Result "SingBox 目标支持" "200" "error"
}
Write-Host ""

# ============================================
# 11. 边界情况和特殊场景
# ============================================
Write-Host "【11. 边界情况和特殊场景】"
Write-Host ""

# 空订阅
$empty = Base64Url-Encode ""
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$empty" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "空订阅返回错误" "400" $resp.StatusCode
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Test-Result "空订阅返回错误" "400" "400"
    } else {
        Test-Result "空订阅返回错误" "400" "其他"
    }
}

# 无效 base64
$invalidB64 = Base64Url-Encode "!!!not-valid-base64!!!"
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$invalidB64" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "无效 base64 返回错误" "400" $resp.StatusCode
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Test-Result "无效 base64 返回错误" "400" "400"
    } else {
        Test-Result "无效 base64 返回错误" "400" "其他"
    }
}

# 多参数组合
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash&url=$vmess&ua=TestUA&global-ua=GlobalUA&proxys-ua=ProxysUA&proxys-provider=false&dedup=true&fetch_timeout=10" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "多参数组合不崩溃" "200" $resp.StatusCode
} catch {
    Test-Result "多参数组合不崩溃" "200" "error"
}

# 未知 target
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=unknown&url=$vmess" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "未知 target 返回 400" "400" $resp.StatusCode
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Test-Result "未知 target 返回 400" "400" "400"
    } else {
        Test-Result "未知 target 返回 400" "400" "其他"
    }
}

# 缺少 url 参数
try {
    $resp = Invoke-WebRequest -Uri "$HostAddr/sub?target=clash" -TimeoutSec 5 -ErrorAction Stop
    Test-Result "缺少 url 参数返回 400" "400" $resp.StatusCode
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Test-Result "缺少 url 参数返回 400" "400" "400"
    } else {
        Test-Result "缺少 url 参数返回 400" "400" "其他"
    }
}
Write-Host ""

# ============================================
# 汇总
# ============================================
Write-Host "=========================================="
Write-Host "测试结果汇总"
Write-Host "=========================================="
Write-Host "通过: $Pass / $Total"
Write-Host "失败: $Fail / $Total"
Write-Host ""

if ($Fail -eq 0) {
    Write-Host "✅ 所有测试通过！"
} else {
    Write-Host "⚠️  有 $Fail 个测试失败"
}

# 清理
Stop-Job -Id $FakeServer.Id -ErrorAction SilentlyContinue
Remove-Job -Id $FakeServer.Id -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Docker 镜像保留: subconverter-extended:test (您还有别的要测试)"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | Select-String "subconverter"

Write-Host ""
Write-Host "Docker 容器状态:"
docker ps --filter "name=subconverter" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

exit $Fail
