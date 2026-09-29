// Browser printing without another pubspec dependency. JS web builds supported.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class CardPrintHost {
  static const canOpenBrowser = true;
  String? _url;
  Future<String> prepare(String document) async {
    await close();
    return _url = html.Url.createObjectUrlFromBlob(
      html.Blob([document], 'text/html'),
    );
  }

  void openBrowser(String url) {
    html.window.open(url, '_blank');
  }

  Future<void> close() async {
    if (_url != null) html.Url.revokeObjectUrl(_url!);
    _url = null;
  }
}
