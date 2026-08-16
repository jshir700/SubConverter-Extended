# SubConverter-Extended 编译与测试计划

> 生成时间：2026-08-16
> 目标：验证 Fork (jshir700) 功能与 Origin 代码的兼容性

---

## 一、编译环境准备

### 1.1 环境检查

```bash
# 检查必要工具
cmake --version
go version
python3 --version
g++ --version

# 检查依赖
pkg-config --modversion libcurl
pkg-config --modversion pcre2
pkg-config --modversion yaml-cpp
```

### 1.2 构建配置

```bash
# 基本构建
cmake -B build -DCMAKE_BUILD_TYPE=Release

# 启用测试（可选）
cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=ON

# 启用 Sanitizer（调试用）
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DENABLE_SANITIZERS=ON
```

### 1.3 编译命令

```bash
# 单架构构建
cmake --build build -j$(nproc)

# Windows (MSYS2)
cmake --build build -j8

# Docker 构建（测试镜像）
docker build -t subconverter-extended:test-dedup -f Dockerfile .
```

---

## 二、测试策略

### 2.1 测试分类

| 类别 | 测试内容 | 优先级 |
|------|----------|--------|
| **编译验证** | 检查代码能否正常编译 | P0 |
| **单元测试** | C++ 单元测试 + Python 测试 | P1 |
| **功能测试** | Fork 独有功能验证 | P1 |
| **兼容性测试** | Origin 功能验证 | P2 |
| **压力测试** | 并发/大订阅测试 | P3 |

### 2.2 测试覆盖矩阵

```
┌─────────────────────────────────────────────────────────────┐
│                    Fork 功能测试覆盖                         │
├─────────────────┬──────────────┬──────────────┬─────────────┤
│ 功能模块        │ 单元测试      │ 集成测试      │ 兼容性测试   │
├─────────────────┼──────────────┼──────────────┼─────────────┤
│ dedup           │ test_dedup.py│ ✅           │ ✅           │
│ ua/fetch_timeout│ 新建         │ ✅           │ ✅           │
│ per-URL 参数    │ 新建         │ ✅           │ ✅           │
│ panic recovery  │ 新建         │ ✅           │ ✅           │
│ 相对路径修复    │ 新建         │ ✅           │ ✅           │
│ Mieru/Age/Stash │ mieru_uri_test│ ✅          │ ✅           │
│ v2 统计         │ 新建         │ ✅           │ ✅           │
└─────────────────┴──────────────┴──────────────┴─────────────┘
```

---

## 三、测试用例设计

### 3.1 Dedup 功能测试

#### 3.1.1 /getruleset 去重测试

**测试用例 1：Surge 格式去重（type=1）**
```bash
# 构造重复规则
cat > /tmp/test_surge.txt << 'EOF'
DOMAIN,dup1.com,PROXY
DOMAIN,dup1.com,DIRECT
DOMAIN,unique1.com,PROXY
DOMAIN-SUFFIX,dup2.net,PROXY
DOMAIN-SUFFIX,dup2.net,PROXY
EOF

# 测试 dedup=true
curl "http://localhost:25500/getruleset?url=$(echo -n 'RULE,http://localhost:18083/surge&type=1' | base64)&type=1&dedup=true"

# 预期：去重后只有 3 条规则
# DOMAIN,dup1.com,PROXY
# DOMAIN,unique1.com,PROXY
# DOMAIN-SUFFIX,dup2.net,PROXY
```

**测试用例 2：Clash 格式去重（type=3-6）**
```bash
# Clash DOMAIN (type=3)
curl "http://localhost:25500/getruleset?url=$(echo -n 'RULE,http://localhost:18083/clash-domain&type=3' | base64)&type=3&dedup=true"

# Clash IP-CIDR (type=4) - 测试 no-resolve 区分
curl "http://localhost:25500/getruleset?url=$(echo -n 'RULE,http://localhost:18083/clash-ipcidr&type=4' | base64)&type=4&dedup=true"

# 预期：IP-CIDR,10.0.0.0/8 和 IP-CIDR,10.0.0.0/8,no-resolve 视为不同规则
```

**测试用例 3：禁用去重（dedup=false）**
```bash
curl "http://localhost:25500/getruleset?url=$(echo -n 'RULE,http://localhost:18083/surge&type=1' | base64)&type=1&dedup=false"

# 预期：保留所有重复规则
```

#### 3.1.2 /sub 内联规则去重测试

```bash
# 构造包含重复规则的订阅
cat > /tmp/test_sub.txt << 'EOF'
[Rule]
DOMAIN,dup1.com,PROXY
DOMAIN,dup1.com,DIRECT
DOMAIN,unique1.com,PROXY
EOF

# 测试 dedup 参数
curl "http://localhost:25500/sub?target=clash&url=$(echo -n 'http://localhost:18083/test_sub.txt' | base64)&dedup=true&rules-provider=false"

# 预期：输出中无重复规则
```

### 3.2 UA 参数测试

#### 3.2.1 &ua= 参数测试

**测试用例 1：基本 UA 覆盖**
```bash
# 测试 &ua= 参数
curl -H "User-Agent: Mozilla/5.0" \
  "http://localhost:25500/sub?target=clash&url=$(echo -n 'http://test.com/sub' | base64)&ua=MyApp/1.0"

# 检查日志中的 UA 是否被覆盖
```

**测试用例 2：UA 优先级链**
```bash
# 测试优先级：per-URL |ua > &proxys-ua= > &ua= > &global-ua=

# 场景 1：global-ua 覆盖
curl "http://localhost:25500/sub?target=clash&url=$(echo -n 'http://test.com/sub' | base64)&global-ua=GlobalUA/1.0"

# 场景 2：&ua= 优先于 global-ua
curl "http://localhost:25500/sub?target=clash&url=$(echo -n 'http://test.com/sub' | base64)&global-ua=GlobalUA/1.0&ua=RequestUA/1.0"

# 场景 3：&proxys-ua= 优先于 &ua=
curl "http://localhost:25500/sub?target=clash&url=$(echo -n 'http://test.com/sub' | base64)&proxys-provider=false&proxys-ua=ProxysUA/1.0&ua=RequestUA/1.0"
```

#### 3.2.2 Per-URL |ua= 参数测试

```bash
# 测试 per-URL UA 参数
curl "http://localhost:25500/sub?target=clash&url=http://test1.com/sub|ua=URL1UA/1.0;http://test2.com/sub|ua=URL2UA/1.0"

# 预期：URL1 使用 URL1UA/1.0，URL2 使用 URL2UA/1.0
```

### 3.3 超时控制测试

#### 3.3.1 &fetch_timeout= 参数测试

**测试用例 1：正常超时设置**
```bash
# 测试 5 秒超时
curl -w "%{time_total}\n" \
  "http://localhost:25500/getruleset?url=$(echo -n 'http://slow-server.com/rules' | base64)&type=1&fetch_timeout=5"

# 预期：请求在 5 秒内返回或超时
```

**测试用例 2：超时恢复**
```bash
# 第一次请求设置超时
curl "http://localhost:25500/getruleset?url=xxx&type=1&fetch_timeout=5"

# 第二次请求应使用默认超时（15 秒）
curl "http://localhost:25500/getruleset?url=xxx&type=1"
```

### 3.4 Per-URL 参数测试

#### 3.4.1 订阅链接 Per-URL 参数

**测试用例 1：|provider= 参数**
```bash
# URL1 使用 provider 模式（默认）
# URL2 内联为节点
curl "http://localhost:25500/sub?target=clash&url=http://test1.com/sub;http://test2.com/sub|provider=false"

# 预期：URL1 生成 proxy-provider，URL2 内联为节点
```

**测试用例 2：|proxy= 参数**
```bash
# 使用 SOCKS5 代理
curl "http://localhost:25500/sub?target=clash&url=http://test.com/sub|proxy=socks5://127.0.0.1:1080"

# 预期：该订阅使用指定代理下载
```

**测试用例 3：|interval= 参数**
```bash
# 自定义更新间隔
curl "http://localhost:25500/sub?target=clash&url=http://test.com/sub|interval=3600"

# 预期：proxy-provider 的 interval 为 3600 秒
```

### 3.5 Mihomo Panic Recovery 测试

**测试用例 1：正常订阅**
```bash
curl "http://localhost:25500/sub?target=clash&url=$(echo -n 'http://test.com/sub' | base64)"

# 预期：正常返回
```

**测试用例 2：恶意订阅（触发 panic）**
```bash
# 构造可能触发 mihomo panic 的订阅
cat > /tmp/malicious.txt << 'EOF'
vmess://invalid-base64-data-that-may-cause-panic
EOF

curl -w "%{http_code}\n" \
  "http://localhost:25500/sub?target=clash&url=$(cat /tmp/malicious.txt | base64)"

# 预期：进程不崩溃，返回错误信息
# {"error": "mihomo parser panic: ..."}
```

### 3.6 反向代理子路径测试

**测试用例 1：Dashboard 访问**
```bash
# 正常路径访问
curl -s "http://localhost:25500/dashboard" | grep "favicon"

# 预期：使用相对路径 ./version/favicon-dark.svg
```

**测试用例 2：子路径访问**
```bash
# 模拟子路径部署
curl -H "X-Forwarded-Prefix: /subconverter" \
  -s "http://localhost:25500/dashboard" | grep "fetch.*dashboard"

# 预期：使用相对路径 dashboard/data
```

### 3.7 节点类型测试

#### 3.7.1 基础节点类型

**测试用例 1：VMess 节点**
```bash
cat > /tmp/vmess.txt << 'EOF'
vmess://eyJ2IjoiMiIsInBzIjoiVGVzdCIsImFkZCI6IjEuMi4zLjQiLCJwb3J0IjoiMTIzNCIsImlkIjoiMTIzNDU2NzgtaWRlbnt7eyJpZCI6IjEyMzQ1Njc4LWlkZW50aWZpZXIifX19fX0=
EOF

curl "http://localhost:25500/sub?target=clash&url=$(cat /tmp/vmess.txt | base64)"
```

**测试用例 2：VLESS 节点**
```bash
cat > /tmp/vless.txt << 'EOF'
vless://id@host:port?type=tcp&security=tls#Test
EOF

curl "http://localhost:25500/sub?target=clash&url=$(cat /tmp/vless.txt | base64)"
```

**测试用例 3：Trojan 节点**
```bash
cat > /tmp/trojan.txt << 'EOF'
trojan://password@host:port#Test
EOF

curl "http://localhost:25500/sub?target=clash&url=$(cat /tmp/trojan.txt | base64)"
```

#### 3.7.2 Origin 新增协议测试

**测试用例 4：Mieru 协议**
```bash
cat > /tmp/mieru.txt << 'EOF'
mieru://host:port?security=aes-128-gcm&plugin=...
EOF

curl "http://localhost:25500/sub?target=clash&url=$(cat /tmp/mieru.txt | base64)"
```

**测试用例 5：Age 加密订阅**
```bash
# 测试 Age 加密订阅解析（需要公钥）
curl "http://localhost:25500/sub?target=clash&url=$(echo -n 'age://encrypted-data' | base64)"
```

**测试用例 6：Stash 配置生成**
```bash
curl "http://localhost:25500/sub?target=stash&url=$(echo -n 'http://test.com/sub' | base64)"
```

### 3.8 Provider 参数测试

#### 3.8.1 &proxys-provider= 参数

**测试用例 1：启用 proxy-provider（默认）**
```bash
curl "http://localhost:25500/sub?target=clash&url=http://test.com/sub"

# 预期：输出包含 proxy-providers 字段
```

**测试用例 2：禁用 proxy-provider**
```bash
curl "http://localhost:25500/sub?target=clash&url=http://test.com/sub&proxys-provider=false"

# 预期：输出不含 proxy-providers，节点直接内联
```

#### 3.8.2 &rules-provider= 参数

**测试用例 3：启用 rule-provider（默认）**
```bash
curl "http://localhost:25500/sub?target=clash&url=http://test.com/sub&rules=http://test.com/rules"

# 预期：输出包含 rule-providers 字段
```

**测试用例 4：禁用 rule-provider**
```bash
curl "http://localhost:25500/sub?target=clash&url=http://test.com/sub&rules=http://test.com/rules&rules-provider=false"

# 预期：规则内联到 rules 字段
```

### 3.9 测试配置文件

#### 3.9.1 测试订阅 fixture

```yaml
# tests/fixtures/test_subscription.yaml
proxies:
  - {name: "Test-VMess", type: vmess, server: 1.2.3.4, port: 1234, uuid: "12345678-1234-1234-1234-123456789abc", alterId: 0, cipher: auto}
  - {name: "Test-Trojan", type: trojan, server: 1.2.3.4, port: 1234, password: test}
  - {name: "Test-VLESS", type: vless, server: 1.2.3.4, port: 1234, uuid: "12345678-1234-1234-1234-123456789abc", network: tcp}

proxy-groups:
  - {name: "Test-Group", type: select, proxies: ["Test-VMess", "Test-Trojan", "Test-VLESS"]}

rules:
  - "DOMAIN,example.com,DIRECT"
  - "DOMAIN-SUFFIX,example.com,PROXY"
  - "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
```

---

## 四、测试执行流程

### 4.1 快速验证（5 分钟）

```bash
# 1. 编译
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8

# 2. 运行基础测试
cd build
ctest --output-on-failure -E "external"

# 3. 运行 dedup 测试
python ../tests/test_dedup.py
```

### 4.2 完整测试（30 分钟）

```bash
# 1. 编译所有测试
cmake -B build -DBUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8

# 2. 运行所有测试
cd build
ctest --output-on-failure

# 3. 运行 Python 测试
python ../tests/test_dedup.py
python ../tests/test_inline_dedup.ini

# 4. 运行 Docker 测试
docker build -t subconverter-extended:test .
docker run --rm -p 25500:25500 subconverter-extended:test
# 另开终端运行功能测试
```

### 4.3 压力测试（可选）

```bash
# 并发请求测试
for i in {1..100}; do
  curl -s "http://localhost:25500/sub?target=clash&url=xxx" &
done
wait

# 大订阅测试（10万+ 节点）
curl -X POST -F "file=@large_subscription.txt" http://localhost:25500/upload
curl "http://localhost:25500/sub?target=clash&url=http://localhost:25500/getfile/large_subscription.txt"
```

---

## 五、测试报告模板

### 5.1 测试结果汇总

```markdown
## 测试结果

| 测试类别 | 用例数 | 通过 | 失败 | 跳过 |
|---------|--------|------|------|------|
| 编译验证 | 1 | ✅ | - | - |
| Dedup 功能 | 10 | 9 | 1 | - |
| UA 参数 | 8 | 8 | - | - |
| 超时控制 | 4 | 4 | - | - |
| Per-URL 参数 | 6 | 6 | - | - |
| Panic Recovery | 3 | 3 | - | - |
| Origin 功能 | 20 | 20 | - | - |
| **总计** | **52** | **50** | **1** | **-** |

### 失败用例
- test_dedup_surge_type1: 规则去重 key 计算错误
```

### 5.2 性能基准

```markdown
## 性能测试

| 场景 | 请求数 | 平均响应时间 | P99 时间 | 内存峰值 |
|------|--------|-------------|----------|----------|
| 小订阅（100 节点） | 100 | 15ms | 25ms | 50MB |
| 中订阅（1000 节点） | 50 | 45ms | 80ms | 120MB |
| 大订阅（10000 节点） | 10 | 200ms | 350ms | 500MB |
| 并发（100 请求） | 100 | 50ms | 120ms | 200MB |
```

---

## 六、测试环境要求

### 6.1 编译环境

- CMake 3.13+
- GCC 9+ / Clang 10+ / MSVC 2019+
- Go 1.21+
- Python 3.8+

### 6.2 测试环境

```bash
# 启动测试服务器
./build/subconverter -f base/pref.example.ini

# 或使用 Docker
docker run -d -p 25500:25500 --name subconverter subconverter-extended:test
```

### 6.3 测试工具

```bash
# HTTP 测试
curl, wget

# Python 测试框架
pytest, requests

# 性能测试
wrk, ab (Apache Bench)
```

---

## 七、测试优先级

### P0 - 必须通过

1. 编译成功
2. Dedup 基础功能
3. UA 参数基本功能
4. Per-URL 参数解析

### P1 - 重要功能

5. fetch_timeout 超时控制
6. Mihomo panic recovery
7. Origin 核心功能（Mieru/Age/Stash）
8. Dashboard 相对路径

### P2 - 增强功能

9. 完整测试套件
10. 性能基准测试
11. 压力测试

### P3 - 可选

12. 模糊测试
13. 安全性测试

---

## 八、下一步行动

1. **立即执行**：快速验证（5 分钟）
2. **编译验证**：检查所有文件能否正常编译
3. **功能测试**：按优先级执行测试用例
4. **报告结果**：填写测试报告模板
5. **修复问题**：修复发现的 bug
6. **回归测试**：确保修复不引入新问题

---

*测试计划生成时间：2026-08-16*
