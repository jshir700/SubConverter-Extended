"""Dedup integration tests for /getruleset (6 types) and /sub inline rules."""
import base64
import http.server
import json
import os
import socketserver
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

# ============================================================
# Configuration
# ============================================================
HOST_IP = "192.168.31.238"  # change to your LAN IP
FAKE_PORT = 18083
SUBC_PORT = 25502
IMAGE_NAME = "subconverter-extended:test-dedup"
CONTAINER_NAME = "subconverter-dedup-test"

# ============================================================
# Fake ruleset server
# ============================================================
RULESETS = {
    "/surge": (
        "DOMAIN,dup1.com,PROXY\n"
        "DOMAIN,dup1.com,DIRECT\n"         # dup TYPE,VALUE
        "DOMAIN,unique1.com,PROXY\n"
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"   # exact dup
    ),
    "/quanx": (
        "DOMAIN,dup1.com,PROXY\n"
        "DOMAIN,dup1.com,DIRECT\n"
        "DOMAIN,unique1.com,PROXY\n"
        "IP-CIDR,10.0.0.0/8,DIRECT\n"
        "IP-CIDR,10.0.0.0/8,PROXY\n"      # dup TYPE,VALUE (no no-resolve)
    ),
    "/clash-domain": (
        "DOMAIN,dup1.com\n"
        "DOMAIN,dup1.com\n"                # exact dup
        "DOMAIN-SUFFIX,dup2.net\n"
        "DOMAIN-SUFFIX,dup2.net\n"         # exact dup
        "DOMAIN,unique1.com\n"
        "DOMAIN-SUFFIX,unique2.org\n"
    ),
    "/clash-ipcidr": (
        "IP-CIDR,10.0.0.0/8\n"
        "IP-CIDR,10.0.0.0/8\n"            # exact dup
        "IP-CIDR,10.0.0.0/8,no-resolve\n"  # different key (has no-resolve)
        "IP-CIDR6,2001:db8::/32\n"
        "IP-CIDR,172.16.0.0/12\n"
    ),
    "/clash-classical": (
        "DOMAIN,dup1.com,PROXY\n"
        "DOMAIN,dup1.com,DIRECT\n"         # dup TYPE,VALUE
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"   # exact dup
        "IP-CIDR,10.0.0.0/8,PROXY,no-resolve\n"
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n"  # dup TYPE,VALUE,no-resolve
        "MATCH,DIRECT\n"
    ),
    "/surge-domainset": (
        "DOMAIN,dup1.com\n"
        "DOMAIN,dup1.com\n"                # exact dup
        "DOMAIN-SUFFIX,dup2.net\n"
        "DOMAIN-SUFFIX,dup2.net\n"         # exact dup
        "DOMAIN,unique1.com\n"
    ),
}


class QuietHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        content = RULESETS.get(self.path)
        if content is None:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(content.encode())

    def log_message(self, fmt, *args):
        pass


def start_fake_server():
    server = socketserver.TCPServer(("0.0.0.0", FAKE_PORT), QuietHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    print(f"[OK] Fake ruleset server on :{FAKE_PORT}")
    return server


# ============================================================
# Docker helpers
# ============================================================
def run(cmd, check=True):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"[FAIL] {cmd}\n{result.stderr}")
        sys.exit(1)
    return result.stdout.strip()


def b64url(s):
    return base64.urlsafe_b64encode(s.encode()).decode().rstrip("=")


# ============================================================
# Test cases
# ============================================================
# (type_int, path, expected_unique_rules)
GETRULESET_TESTS = [
    # type 1: Surge — 5 rules, 3 unique (2 DOMAIN,dup1 + 2 DOMAIN-SUFFIX,dup2)
    (1, "/surge", 3),
    # type 2: Quantumult X — 5 rules, 3 unique
    (2, "/quanx", 3),
    # type 3: Clash domain rule-provider — 6 rules, 4 unique
    (3, "/clash-domain", 4),
    # type 4: Clash ipcidr rule-provider — 5 rules, 4 unique
    # (IP-CIDR,10.0.0.0/8 and IP-CIDR,10.0.0.0/8,no-resolve are DIFFERENT keys)
    (4, "/clash-ipcidr", 4),
    # type 5: Surge DOMAIN-SET — 5 rules, 3 unique
    (5, "/surge-domainset", 3),
    # type 6: Clash classical — 7 rules, 4 unique
    # (DOMAIN,dup1 x2 + DOMAIN-SUFFIX,dup2 x2 + IP-CIDR,10.0.0.0,no-resolve x2 + MATCH)
    (6, "/clash-classical", 4),
]


def count_output_lines(output, type_int):
    """Count meaningful rule lines in /getruleset output."""
    lines = output.strip().split("\n")
    if type_int in (3, 4, 6):
        # payload: header + indented rules
        rules = [l for l in lines if l.strip().startswith("- ")]
    elif type_int == 5:
        # plain lines, skip empty
        rules = [l for l in lines if l.strip() and not l.startswith("#")]
    else:
        # type 1,2: plain lines
        rules = [l for l in lines if l.strip()]
    return len(rules)


def test_getruleset(type_int, path, expected_unique):
    """Test /getruleset with dedup=true and dedup=false."""
    url = b64url(f"http://{HOST_IP}:{FAKE_PORT}{path}")
    group = "PROXY"

    # Test with dedup=true
    req = f"http://localhost:{SUBC_PORT}/getruleset?url={url}&type={type_int}&group={group}&dedup=true"
    resp = urllib.request.urlopen(req, timeout=10)
    content_dedup_on = resp.read().decode()
    count_on = count_output_lines(content_dedup_on, type_int)

    # Test with dedup=false
    req = f"http://localhost:{SUBC_PORT}/getruleset?url={url}&type={type_int}&group={group}&dedup=false"
    resp = urllib.request.urlopen(req, timeout=10)
    content_dedup_off = resp.read().decode()
    count_off = count_output_lines(content_dedup_off, type_int)

    ok_on = count_on == expected_unique
    ok_off = count_off > count_on  # dedup=false should have more rules

    status = "OK" if ok_on and ok_off else "FAIL"
    print(f"  [{status}] type={type_int} ({path}): dedup=true → {count_on} (expected {expected_unique}), dedup=false → {count_off}")

    if not ok_on:
        print(f"    dedup=true output:\n{content_dedup_on[:500]}")
    if not ok_off:
        print(f"    dedup=false output:\n{content_dedup_off[:500]}")

    return ok_on and ok_off


# ============================================================
# /sub inline rules dedup test
# ============================================================
def test_sub_inline_dedup():
    """Test /sub endpoint with inline rules and dedup=true/false."""
    # Config with duplicate inline rules
    config = """proxies:
  - {name: test, server: 1.2.3.4, port: 443, type: ss, cipher: aes-128-gcm, password: pass}
proxy-groups:
  - {name: PROXY, type: select, proxies: [test]}
rules:
  - DOMAIN,inline-dup.com,PROXY
  - DOMAIN,inline-dup.com,PROXY
  - DOMAIN-SUFFIX,inline-suffix.net,PROXY
  - DOMAIN-SUFFIX,inline-suffix.net,PROXY
  - MATCH,DIRECT
"""

    def count_rules(yaml_text):
        """Count rules in output YAML."""
        in_rules = False
        count = 0
        for line in yaml_text.split("\n"):
            if line.startswith("rules:"):
                in_rules = True
                continue
            if in_rules:
                if line.startswith("  - "):
                    count += 1
                elif line and not line.startswith(" "):
                    break
        return count

    # Test dedup=true
    req = urllib.request.Request(
        f"http://localhost:{SUBC_PORT}/sub?target=clash&dedup=true",
        data=config.encode(),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    resp = urllib.request.urlopen(req, timeout=10)
    count_on = count_rules(resp.read().decode())

    # Test dedup=false
    req = urllib.request.Request(
        f"http://localhost:{SUBC_PORT}/sub?target=clash&dedup=false",
        data=config.encode(),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    resp = urllib.request.urlopen(req, timeout=10)
    count_off = count_rules(resp.read().decode())

    # With dedup=true: MATCH + 2 unique = 3 rules
    # With dedup=false: MATCH + 4 = 5 rules
    ok_on = count_on == 3
    ok_off = count_off == 5

    status = "OK" if ok_on and ok_off else "FAIL"
    print(f"  [{status}] /sub inline rules: dedup=true → {count_on} (expected 3), dedup=false → {count_off} (expected 5)")

    return ok_on and ok_off


# ============================================================
# Main
# ============================================================
def main():
    print("=== Dedup Integration Tests ===\n")

    # 1. Start fake server
    server = start_fake_server()

    # 2. Build Docker image
    print("[...] Building Docker image...")
    run(
        f'docker build -t {IMAGE_NAME} -f Dockerfile .',
    )
    print("[OK] Docker image built")

    # 3. Start container with public security profile
    print("[...] Starting test container...")
    run(f"docker rm -f {CONTAINER_NAME}", check=False)
    run(
        f"docker run -d --name {CONTAINER_NAME} "
        f"-p {SUBC_PORT}:25500 "
        f"-e SUBCONVERTER_SECURITY_PROFILE=public "
        f"{IMAGE_NAME}"
    )
    time.sleep(3)
    logs = run(f"docker logs --tail 3 {CONTAINER_NAME}", check=False)
    print(f"[OK] Container started: {logs.split(chr(10))[-1].strip()}")

    all_ok = True

    # 4. Test /getruleset for all 6 types
    print("\n--- /getruleset dedup tests ---")
    for type_int, path, expected in GETRULESET_TESTS:
        ok = test_getruleset(type_int, path, expected)
        all_ok = all_ok and ok

    # 5. Test /sub inline rules dedup
    print("\n--- /sub inline rules dedup test ---")
    ok = test_sub_inline_dedup()
    all_ok = all_ok and ok

    # 6. Cleanup
    print("\n[...] Cleaning up...")
    run(f"docker rm -f {CONTAINER_NAME}", check=False)
    run(f"docker rmi {IMAGE_NAME}", check=False)
    server.shutdown()

    if all_ok:
        print("\n=== ALL TESTS PASSED ===")
        sys.exit(0)
    else:
        print("\n=== SOME TESTS FAILED ===")
        sys.exit(1)


if __name__ == "__main__":
    main()
