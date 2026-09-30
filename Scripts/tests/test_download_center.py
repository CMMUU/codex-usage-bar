import importlib.util
import pathlib
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

spec = importlib.util.spec_from_file_location('verify_center', pathlib.Path(__file__).parents[1] / 'verify_download_center.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class HeadRedirectTests(unittest.TestCase):
    def test_head_remains_head_across_installer_redirects(self):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_HEAD(self):
                requests.append(('HEAD', self.path))
                if self.path.startswith('/redirect/'):
                    self.send_response(int(self.path.rsplit('/', 1)[1]))
                    self.send_header('Location', '/installer')
                else:
                    self.send_response(200)
                    self.send_header('Content-Length', '4000000')
                self.end_headers()
            def do_GET(self):
                requests.append(('GET', self.path))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'unexpected GET')
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            for status in (301, 302, 303, 307):
                with self.subTest(status=status):
                    body, headers = module.get(f'http://127.0.0.1:{server.server_port}/redirect/{status}', method='HEAD', limit=1)
                    self.assertEqual(body, b'')
                    self.assertEqual(headers['Content-Length'], '4000000')
            self.assertEqual(requests, [(method, path) for code in (301, 302, 303, 307) for method, path in [('HEAD', f'/redirect/{code}'), ('HEAD', '/installer')]])
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

if __name__ == '__main__':
    unittest.main()
