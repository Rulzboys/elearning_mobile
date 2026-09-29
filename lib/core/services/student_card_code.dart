/// A permanent lookup reference, never a login token or proof of attendance.
class StudentCardCode {
  static final _uuid =
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  static String encode(String tenantId, String studentId) =>
      'ELRNCARD1:$tenantId:$studentId';
  static ({String tenantId, String studentId})? decode(String value) {
    final match = RegExp(
      '^ELRNCARD1:($_uuid):($_uuid)\$',
    ).firstMatch(value.trim());
    return match == null
        ? null
        : (tenantId: match.group(1)!, studentId: match.group(2)!);
  }
}
