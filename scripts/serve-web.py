"""Serve the Godot web export (godot/build/web) on localhost without browser caching, for testing."""
import http.server
import os
import sys


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 5235
os.chdir(os.path.join(os.path.dirname(__file__), '..', 'godot', 'build', 'web'))
http.server.ThreadingHTTPServer(('127.0.0.1', port), NoCache).serve_forever()
