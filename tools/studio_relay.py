#!/usr/bin/env python3
"""Serves one .rbxm to Roblox Studio so an MCP snippet can import it (lucky blocks, 2026-10-03).

Studio can't read files from disk, but HttpService can fetch from this machine. This serves the
file base64-encoded at http://127.0.0.1:8765/file until Ctrl+C (or `pkill -f studio_relay.py`).
The Studio side (EncodingService + SerializationService) is in assets/luckyblocks/Readme.md.

    python3 tools/studio_relay.py assets/luckyblocks/models/AdvancedLuckyBlock.rbxm
"""
import base64
import http.server
import sys

PORT = 8765

if len(sys.argv) != 2:
    sys.exit("usage: studio_relay.py <file.rbxm>")
with open(sys.argv[1], "rb") as f:
    BODY = base64.b64encode(f.read())


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/file":
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *args):
        pass


print(f"serving {sys.argv[1]} ({len(BODY)} base64 bytes) at http://127.0.0.1:{PORT}/file")
http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
