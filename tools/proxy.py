#!/usr/bin/env python3

import http.server
import urllib.request
import threading

TARGET = "127.0.0.1:18088"

ROUTES = {
    8081: "app1.com",
    8082: "app2.com",
    8083: "app3.com",
}

def make_handler(fake_host):
    class Proxy(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            headers = {"Host": fake_host}
            req = urllib.request.Request(f"http://{TARGET}{self.path}", headers=headers)
            try:
                with urllib.request.urlopen(req) as resp:
                    self.send_response(resp.status)
                    for k, v in resp.getheaders():
                        if k.lower() not in ("transfer-encoding", "connection"):
                            self.send_header(k, v)
                    self.end_headers()
                    self.wfile.write(resp.read())
            except Exception as e:
                self.send_response(502)
                self.end_headers()
                self.wfile.write(str(e).encode())

        def log_message(self, fmt, *args):
            print(f"[:{self.server.server_port}] {fmt % args}")

    return Proxy

def serve(port, fake_host):
    server = http.server.HTTPServer(("127.0.0.1", port), make_handler(fake_host))
    print(f"Proxy listening: http://127.0.0.1:{port} -> Host: {fake_host}")
    server.serve_forever()

if __name__ == "__main__":
    threads = []
    for port, host in ROUTES.items():
        t = threading.Thread(target=serve, args=(port, host), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
