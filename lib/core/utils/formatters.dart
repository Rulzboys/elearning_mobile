import 'package:intl/intl.dart';

class Formatters {
  static String date(DateTime d) =>
      DateFormat('dd MMM yyyy', 'id_ID').format(d.toLocal());
  static String dateTime(DateTime d) =>
      DateFormat('dd MMM, HH:mm', 'id_ID').format(d.toLocal());
  static String dateText(String s) {
    final d = DateTime.tryParse(s);
    return d == null ? s : date(d);
  }

  static const days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  static String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}
