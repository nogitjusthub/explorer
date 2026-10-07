"""Локальный сервер веб-сборки с приёмом отчётов от игры.

Отдаёт build/web как статику и принимает:
  POST /log   — строка текста, дописывается в build/web_log.txt;
  POST /shot  — PNG в теле запроса, сохраняется в build/web_shots/shot_NN.png.
Игра шлёт туда результаты бенчмарка (?bench=N в адресе страницы) и скриншоты.

Запуск: python tools/scripts/web_server.py [порт]
"""

import functools
import http.server
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
WEB = ROOT / "build" / "web"
LOG = ROOT / "build" / "web_log.txt"
SHOTS = ROOT / "build" / "web_shots"


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        if self.path == "/log":
            with LOG.open("a", encoding="utf-8") as f:
                f.write(body.decode("utf-8", "replace") + "\n")
        elif self.path == "/shot":
            SHOTS.mkdir(parents=True, exist_ok=True)
            index = len(list(SHOTS.glob("shot_*.png")))
            (SHOTS / f"shot_{index:02d}.png").write_bytes(body)
        else:
            self.send_error(404)
            return
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    handler = functools.partial(Handler, directory=str(WEB))
    # Адрес 127.0.0.1, а не localhost: браузер может пойти по IPv6 (::1), где сервер не слушает.
    print(f"Serving {WEB} at http://127.0.0.1:{port} (Ctrl+C to stop)")
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


if __name__ == "__main__":
    main()
