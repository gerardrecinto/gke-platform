from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        sum(i * i for i in range(300000))  # burn a little CPU so the HPA has a signal
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("", 8080), H).serve_forever()
