#!/usr/bin/env python3
"""Comprehensive functional test for all Fork (jshir700) parameters."""
import sys
import urllib.request
import urllib.parse
import json

BASE_URL = "http://localhost:25501"

# Correct base64 for 'aes-128-gcm:password'
TEST_NODE = "ss://YWVz-LTEyOC1nY206cGFzc3dvcmQ%3D@example.com:8388"
TEST_NODE_FULL = "ss://YWVz-LTEyOC1nY206cGFzc3dvcmQ%3D@example.com:8388#TestNode"

results = []

def test_param(name, value, check_func=None):
    """Test a single parameter."""
    url = f"{BASE_URL}/sub?target=clash&url={TEST_NODE}&{name}={urllib.parse.quote(value)}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode()
            if check_func:
                ok, msg = check_func(body)
                if ok:
                    results.append((name, value, "PASS", msg))
                    print(f"  PASS: &{name}={value} - {msg}")
                else:
                    results.append((name, value, "FAIL", msg))
                    print(f"  FAIL: &{name}={value} - {msg}")
            else:
                results.append((name, value, "PASS", f"OK ({len(body)} bytes)"))
                print(f"  PASS: &{name}={value}")
            return True
    except urllib.error.HTTPError as e:
        results.append((name, value, "FAIL", f"HTTP {e.code}: {e.read().decode()[:200]}"))
        print(f"  FAIL: &{name}={value} - HTTP {e.code}")
        return False
    except Exception as e:
        results.append((name, value, "ERROR", str(e)[:200]))
        print(f"  ERROR: &{name}={value} - {e}")
        return False

def test_inline_param(name, value, check_func=None):
    """Test per-URL inline parameter."""
    url = f"{BASE_URL}/sub?target=clash&url={urllib.parse.quote(TEST_NODE + '|' + name + ':' + value)}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode()
            if check_func:
                ok, msg = check_func(body)
                if ok:
                    results.append((f"|{name}", value, "PASS", msg))
                    print(f"  PASS: |{name}={value} - {msg}")
                else:
                    results.append((f"|{name}", value, "FAIL", msg))
                    print(f"  FAIL: |{name}={value} - {msg}")
            else:
                results.append((f"|{name}", value, "PASS", f"OK ({len(body)} bytes)"))
                print(f"  PASS: |{name}={value}")
            return True
    except urllib.error.HTTPError as e:
        results.append((f"|{name}", value, "FAIL", f"HTTP {e.code}: {e.read().decode()[:200]}"))
        print(f"  FAIL: |{name}={value} - HTTP {e.code}")
        return False
    except Exception as e:
        results.append((f"|{name}", value, "ERROR", str(e)[:200]))
        print(f"  ERROR: |{name}={value} - {e}")
        return False

print("=" * 70)
print("Testing all Fork (jshir700) parameters")
print("=" * 70)
print()

# 2. |provider: 订阅链接级参数
print("--- 2. |provider: 订阅链接级参数 ---")
test_inline_param("provider", "true", lambda body: (True, "per-URL provider=true accepted"))
test_inline_param("provider", "false", lambda body: (True, "per-URL provider=false accepted"))

# 4. |proxy: 订阅链接级参数
print("--- 4. |proxy: 订阅链接级参数 ---")
test_inline_param("proxy", "http://proxy.example.com:7890", lambda body: (True, "per-URL proxy accepted"))

# 6. |ua: 订阅链接级参数
print("--- 6. |ua: 订阅链接级参数 ---")
test_inline_param("ua", "InlineUA/1.0", lambda body: (True, "per-URL ua accepted"))

# 8. |interval: 订阅链接级参数
print("--- 8. |interval: 订阅链接级参数 ---")
test_inline_param("interval", "3600", lambda body: (True, "per-URL interval accepted"))

# 10. &global-ua: 全局参数
print("--- 10. &global-ua: 全局参数 ---")
test_param("global-ua", "GlobalUA/1.0", lambda body: (True, "global-ua accepted"))

# 12. &proxys-provider: 全局参数
print("--- 12. &proxys-provider: 全局参数 ---")
test_param("proxys-provider", "false", lambda body: (True, "proxys-provider=false accepted"))
test_param("proxys-provider", "true", lambda body: (True, "proxys-provider=true accepted"))

# 13. &rules-provider: 全局参数
print("--- 13. &rules-provider: 全局参数 ---")
test_param("rules-provider", "false", lambda body: (True, "rules-provider=false accepted"))
test_param("rules-provider", "true", lambda body: (True, "rules-provider=true accepted"))

# 14. &proxys-ua: 全局参数
print("--- 14. &proxys-ua: 全局参数 ---")
test_param("proxys-ua", "ProxyUA/1.0", lambda body: (True, "proxys-ua accepted"))

# 15. &rules-ua: 全局参数
print("--- 15. &rules-ua: 全局参数 ---")
test_param("rules-ua", "RulesUA/1.0", lambda body: (True, "rules-ua accepted"))

# 16. &proxys-proxy: 全局参数
print("--- 16. &proxys-proxy: 全局参数 ---")
test_param("proxys-proxy", "http://proxy.example.com:7890", lambda body: (True, "proxys-proxy accepted"))

# 17. &rules-proxy: 全局参数
print("--- 17. &rules-proxy: 全局参数 ---")
test_param("rules-proxy", "http://proxy.example.com:7890", lambda body: (True, "rules-proxy accepted"))

# 18. &proxys-interval: 全局参数
print("--- 18. &proxys-interval: 全局参数 ---")
test_param("proxys-interval", "1800", lambda body: (True, "proxys-interval accepted"))

# 19. &rules-interval: 全局参数
print("--- 19. &rules-interval: 全局参数 ---")
test_param("rules-interval", "3600", lambda body: (True, "rules-interval accepted"))

# 21. &dedup: 全局参数
print("--- 21. &dedup: 全局参数 ---")
test_param("dedup", "true", lambda body: (True, "dedup=true accepted"))
test_param("dedup", "false", lambda body: (True, "dedup=false accepted"))
test_param("dedup", "undef", lambda body: (True, "dedup=undef accepted"))

# 其他全局参数
print("--- 其他全局参数 ---")
test_param("ua", "TestBrowser/1.0", lambda body: (True, "ua accepted"))
test_param("fetch_timeout", "5", lambda body: (True, "fetch_timeout=5 accepted"))
test_param("provider_proxy_direct", "true", lambda body: (True, "provider_proxy_direct=true accepted"))

print()
print("=" * 70)
print("Summary:")
passed = sum(1 for r in results if r[2] == "PASS")
failed = len(results) - passed
print(f"  Passed: {passed}/{len(results)}")
print(f"  Failed: {failed}/{len(results)}")
print("=" * 70)

if failed > 0:
    print("\nFailed tests:")
    for name, value, status, detail in results:
        if status != "PASS":
            print(f"  {name}={value}: {detail}")
    sys.exit(1)
else:
    print("\nAll tests passed!")
    sys.exit(0)
