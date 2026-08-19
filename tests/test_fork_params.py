#!/usr/bin/env python3
"""Comprehensive test for all Fork (jshir700) parameters."""
import sys
import urllib.request
import urllib.parse

BASE_URL = "http://localhost:25501"
SUB_URL = f"{BASE_URL}/sub"

# Test URL from smoke test (correct base64 for aes-128-gcm:password)
TEST_URL = "ss://YWVz-LTIyOC1nY206cGFzc3dvcmQ@example.com:8388"

# All fork parameters to test (from merge strategy doc)
PARAMS = [
    ("dedup", "true"),
    ("ua", "TestBrowser/1.0"),
    ("fetch_timeout", "5"),
    ("global-ua", "GlobalUA/1.0"),
    ("proxys-provider", "false"),
    ("proxys-ua", "ProxyUA/1.0"),
    ("proxys-proxy", "http://proxy.example.com:7890"),
    ("proxys-interval", "1800"),
    ("rules-provider", "false"),
    ("rules-ua", "RulesUA/1.0"),
    ("rules-proxy", "http://proxy.example.com:7890"),
    ("rules-interval", "3600"),
    ("provider_proxy_direct", "true"),
]

# Per-URL parameters (inline with |)
INLINE_PARAMS = [
    ("ua", "InlineUA/1.0"),
    ("provider", "true"),
    ("proxy", "http://proxy.example.com:7890"),
    ("interval", "3600"),
]

results = []

def test_param(name, value):
    """Test a single parameter."""
    url = f"{SUB_URL}?target=clash&url={urllib.parse.quote(TEST_URL)}&{name}={urllib.parse.quote(value)}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode()
            results.append((name, value, "PASS", f"OK ({len(body)} bytes)"))
            return True
    except urllib.error.HTTPError as e:
        results.append((name, value, "FAIL", f"HTTP {e.code}: {e.read().decode()[:200]}"))
        return False
    except Exception as e:
        results.append((name, value, "ERROR", str(e)[:200]))
        return False

def test_inline_param(name, value):
    """Test per-URL inline parameter."""
    url = f"{SUB_URL}?target=clash&url={urllib.parse.quote(TEST_URL + '|' + name + ':' + value)}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode()
            results.append((f"|{name}", value, "PASS", f"OK ({len(body)} bytes)"))
            return True
    except urllib.error.HTTPError as e:
        results.append((f"|{name}", value, "FAIL", f"HTTP {e.code}: {e.read().decode()[:200]}"))
        return False
    except Exception as e:
        results.append((f"|{name}", value, "ERROR", str(e)[:200]))
        return False

print("=" * 70)
print("Testing all Fork (jshir700) parameters")
print("=" * 70)
print()

# Test global parameters
print("--- Global Parameters ---")
for name, value in PARAMS:
    ok = test_param(name, value)
    status = "PASS" if ok else "FAIL"
    print(f"  {status}: &{name}={value}")

print()

# Test per-URL inline parameters
print("--- Per-URL Inline Parameters ---")
for name, value in INLINE_PARAMS:
    ok = test_inline_param(name, value)
    status = "PASS" if ok else "FAIL"
    print(f"  {status}: |{name}={value}")

# Summary
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
    for name, value, code, detail in results:
        if code != "PASS":
            print(f"  {name}={value}: {detail}")
    sys.exit(1)
else:
    print("\nAll tests passed!")
    sys.exit(0)
