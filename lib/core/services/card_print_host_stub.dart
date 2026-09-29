class CardPrintHost {
  static const canOpenBrowser = false;
  Future<String> prepare(String document) async =>
      throw UnsupportedError('Pencetakan belum tersedia pada perangkat ini.');
  void openBrowser(String url) {}
  Future<void> close() async {}
}
