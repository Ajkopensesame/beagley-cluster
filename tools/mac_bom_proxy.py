#!/usr/bin/env python3
import http.server
import urllib.error
import urllib.parse
import urllib.request


BOM_ORIGIN = "https://www.bom.gov.au"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path != "/cgi-bin/bom.sh":
            self.send_error(404, "unsupported path")
            return

        raw = parsed.query or ""
        path_info, _, tail = raw.partition("&")
        if not (path_info.startswith("/fwo/") or path_info.startswith("/radar/")):
            self.send_error(404, "unsupported target")
            return

        upstream = BOM_ORIGIN + path_info
        if tail:
            upstream += "?" + tail

        request = urllib.request.Request(
            upstream,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "*/*",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                body = response.read()
                self.send_response(response.status)
                self.send_header(
                    "Content-Type",
                    response.headers.get("Content-Type", "application/octet-stream"),
                )
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as error:
            body = error.read()
            self.send_response(error.code)
            self.send_header(
                "Content-Type",
                error.headers.get("Content-Type", "text/plain; charset=utf-8"),
            )
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if body:
                self.wfile.write(body)
        except Exception as error:
            body = str(error).encode("utf-8", "ignore")
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, fmt, *args):
        print("[beagley mac bom proxy] " + (fmt % args), flush=True)


def main():
    server = http.server.ThreadingHTTPServer(("0.0.0.0", 8766), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
