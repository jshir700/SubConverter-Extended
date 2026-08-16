"""Fake HTTP server returning rulesets with deliberate duplicates for dedup testing."""
import http.server
import socketserver
import sys

# Each endpoint returns a ruleset with known duplicates
RULESETS = {
    "/surge": (
        # Surge format: TYPE,VALUE,POLICY — 5 rules, 3 unique
        "DOMAIN,dup1.com,PROXY\n"
        "DOMAIN,dup1.com,DIRECT\n"        # dup: same TYPE,VALUE, different policy
        "DOMAIN,unique1.com,PROXY\n"
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"  # dup: exact duplicate
    ),
    "/quanx": (
        # Quantumult X format similar to Surge
        "DOMAIN,dup1.com,PROXY\n"
        "DOMAIN,dup1.com,DIRECT\n"
        "DOMAIN,unique1.com,PROXY\n"
        "IP-CIDR,10.0.0.0/8,DIRECT\n"
        "IP-CIDR,10.0.0.0/8,PROXY\n"     # dup: same IP, different policy
    ),
    "/clash-domain": (
        # Clash domain rules: DOMAIN/DOMAIN-SUFFIX
        "DOMAIN,dup1.com\n"
        "DOMAIN,dup1.com\n"               # exact dup
        "DOMAIN-SUFFIX,dup2.net\n"
        "DOMAIN-SUFFIX,dup2.net\n"        # exact dup
        "DOMAIN,unique1.com\n"
        "DOMAIN-SUFFIX,unique2.org\n"
    ),
    "/clash-ipcidr": (
        # Clash IP-CIDR rules
        "IP-CIDR,10.0.0.0/8\n"
        "IP-CIDR,10.0.0.0/8\n"           # exact dup
        "IP-CIDR,10.0.0.0/8,no-resolve\n"  # different: has no-resolve
        "IP-CIDR6,2001:db8::/32\n"
        "IP-CIDR,172.16.0.0/12\n"
    ),
    "/clash-classical": (
        # Clash classical: mixed rule types
        "DOMAIN,dup1.com,PROXY\n"
        "DOMAIN,dup1.com,DIRECT\n"        # dup: same TYPE,VALUE
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"
        "DOMAIN-SUFFIX,dup2.net,PROXY\n"  # dup: exact dup
        "IP-CIDR,10.0.0.0/8,PROXY,no-resolve\n"
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n"  # dup: same TYPE,VALUE,no-resolve
        "DOMAIN-KEYWORD,ads,REJECT\n"
        "DOMAIN-KEYWORD,ads,PROXY\n"      # dup: same TYPE,VALUE
        "MATCH,DIRECT\n"
    ),
    "/surge-domainset": (
        # Surge DOMAIN-SET: only DOMAIN/DOMAIN-SUFFIX
        "DOMAIN,dup1.com\n"
        "DOMAIN,dup1.com\n"               # exact dup
        "DOMAIN-SUFFIX,dup2.net\n"
        "DOMAIN-SUFFIX,dup2.net\n"        # exact dup
        "DOMAIN,unique1.com\n"
    ),
    "/inline": (
        # For /sub inline rules testing (raw rule content via config)
        "DOMAIN,inline-dup.com\n"
        "DOMAIN,inline-dup.com\n"
        "DOMAIN-SUFFIX,inline-unique.net\n"
    ),
}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # /ua-check — echoes back the User-Agent header (for UA propagation tests)
        if self.path == "/ua-check":
            ua = self.headers.get("User-Agent", "no-ua")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(f"UA:{ua}\n".encode())
            return

        # /slow?s=N — delays N seconds before responding (for fetch_timeout tests)
        if self.path.startswith("/slow"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            delay = int(qs.get("s", [3])[0])
            import time
            time.sleep(delay)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(f"OK after {delay}s\n".encode())
            return

        content = RULESETS.get(self.path)
        if content is None:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(content.encode())

    def log_message(self, fmt, *args):
        pass  # silent


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18082
    server = socketserver.TCPServer(("0.0.0.0", port), Handler)
    print(f"Fake ruleset server on port {port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
