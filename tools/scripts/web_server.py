"""Локальный сервер веб-сборки с приёмом отчётов от игры.

Отдаёт build/web как статику и принимает:
  POST /log   — строка текста, дописывается в build/web_log.txt;
  POST /shot  — PNG в теле запроса, сохраняется в build/web_shots/shot_NN.png (номер — следующий
                после самого большого из уже лежащих: старые снимки не перезаписываются).
Игра шлёт туда результаты бенчмарка (?bench=N в адресе страницы) и скриншоты. Параметры вроде
?bench, ?seed, ?shots игра берёт из адреса в debug-экспорте (export_web.ps1 -Debug) и в release-сборке,
открытой с 127.0.0.1 / localhost; на GitHub Pages release принимает лишь ?log-slow и ?shader-audit.

Запуск: python tools/scripts/web_server.py [порт]
"""

import functools
import http.server
import pathlib
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]
WEB = ROOT / "build" / "web"
LOG = ROOT / "build" / "web_log.txt"
SHOTS = ROOT / "build" / "web_shots"
_shot_lock = threading.Lock()   # сервер многопоточный: два снимка разом не должны взять один номер


def next_shot_path():
    """Следующий свободный снимок: номер на единицу больше самого большого из shot_NN.png."""
    taken = [int(p.stem[5:]) for p in SHOTS.glob("shot_*.png") if p.stem[5:].isdigit()]
    return SHOTS / f"shot_{max(taken, default=-1) + 1:02d}.png"


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        if self.path == "/log":
            with LOG.open("a", encoding="utf-8") as f:
                f.write(body.decode("utf-8", "replace") + "\n")
        elif self.path == "/shot":
            SHOTS.mkdir(parents=True, exist_ok=True)
            with _shot_lock:
                with next_shot_path().open("xb") as f:   # "x" — никогда не перезаписать существующий
                    f.write(body)
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
