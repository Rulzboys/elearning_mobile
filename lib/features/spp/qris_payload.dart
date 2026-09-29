import '../../shared/models/models.dart';

/// EMV TLV validation only; it does not certify a merchant or bank settlement.
class QrisPayload {
  static int crc(String text) {
    var value = 0xffff;
    for (final byte in text.codeUnits) {
      value ^= byte << 8;
      for (var bit = 0; bit < 8; bit++) {
        value =
            ((value & 0x8000) != 0 ? (value << 1) ^ 0x1021 : value << 1) &
            0xffff;
      }
    }
    return value;
  }

  static String checksum(String body) =>
      '$body${crc(body).toRadixString(16).padLeft(4, '0').toUpperCase()}';
  static String tlv(String tag, String value) =>
      '$tag${value.length.toString().padLeft(2, '0')}$value';
  static Map<String, String> parse(String raw) {
    if (raw.length > 2048 || raw.codeUnits.any((x) => x < 32 || x > 126)) {
      throw const AppFailure('Payload QRIS tidak valid.');
    }
    final fields = <String, String>{};
    var pos = 0;
    while (pos < raw.length) {
      if (pos + 4 > raw.length)
        throw const AppFailure('Struktur QRIS terpotong.');
      final tag = raw.substring(pos, pos + 2);
      final length = int.tryParse(raw.substring(pos + 2, pos + 4));
      if (!RegExp(r'^\d{2}$').hasMatch(tag) ||
          length == null ||
          length < 1 ||
          pos + 4 + length > raw.length ||
          fields.containsKey(tag)) {
        throw const AppFailure('Struktur QRIS tidak valid.');
      }
      fields[tag] = raw.substring(pos + 4, pos + 4 + length);
      pos += 4 + length;
    }
    if (fields['00'] != '01' ||
        !['11', '12'].contains(fields['01']) ||
        fields['53'] != '360' ||
        fields['58'] != 'ID' ||
        (fields['59'] ?? '').trim().isEmpty ||
        (fields['60'] ?? '').trim().isEmpty ||
        fields['52'] == null ||
        fields.keys.lastOrNull != '63' ||
        fields['63']?.length != 4 ||
        checksum(raw.substring(0, raw.length - 4)) != raw ||
        !fields.entries.any(
          (e) =>
              (int.tryParse(e.key) ?? 0) >= 26 &&
              (int.tryParse(e.key) ?? 100) <= 51,
        )) {
      throw const AppFailure(
        'Gunakan QRIS merchant Indonesia yang valid (CRC, IDR, dan identitas lengkap).',
      );
    }
    return fields;
  }

  static String validateStatic(String raw) {
    final f = parse(raw);
    if (f['01'] != '11' ||
        f.containsKey('54') ||
        ['55', '56', '57'].any(f.containsKey)) {
      throw const AppFailure(
        'Gunakan QRIS statis tanpa nominal, tip, atau biaya tambahan.',
      );
    }
    return f['59']!;
  }

  static String withAmount(String raw, int amount) {
    validateStatic(raw);
    if (amount < 1 || amount > 10000000)
      throw const AppFailure('Nominal harus Rp1 sampai Rp10.000.000.');
    final f = parse(raw)..['01'] = '12';
    f['54'] = amount.toString();
    f.remove('63');
    final tags = f.keys.toList()..sort();
    return checksum('${tags.map((tag) => tlv(tag, f[tag]!)).join()}6304');
  }
}
