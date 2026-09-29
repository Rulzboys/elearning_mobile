import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Loopback only: no student data is published to the internet or local network.
class CardPrintHost {
  static const canOpenBrowser = false;
  HttpServer? _server;
  Future<String> prepare(String document) async {
    await close();
    final token = base64UrlEncode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    );
    final path = '/kartu/$token';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      try {
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.headers.set('X-Content-Type-Options', 'nosniff');
        request.response.headers.set('Referrer-Policy', 'no-referrer');
        request.response.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
        );
        if (request.method == 'GET' && request.uri.path == path) {
          request.response.headers.contentType = ContentType.html;
          request.response.write(document);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      } catch (_) {
        /* The browser may cancel a request while closing. */
      }
    });
    return 'http://127.0.0.1:${server.port}$path';
  }

  void openBrowser(String url) {}
  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
