import 'dart:convert';

class ProgressReportRow {
  const ProgressReportRow({
    required this.name,
    required this.classroom,
    required this.completed,
    required this.target,
    required this.submissions,
    required this.averageScore,
    required this.present,
    required this.attendanceTotal,
  });

  final String name;
  final String classroom;
  final int completed;
  final int target;
  final int submissions;
  final String averageScore;
  final int present;
  final int attendanceTotal;
}

String progressReportDocument({
  required String school,
  required String generatedAt,
  required List<ProgressReportRow> rows,
}) {
  const escape = HtmlEscape();
  String e(Object value) => escape.convert(value.toString());
  final body = rows.isEmpty
      ? '<tr><td colspan="8" class="empty">Belum ada data perkembangan.</td></tr>'
      : rows
            .map(
              (row) =>
                  '''<tr>
<td>${e(row.name)}</td><td>${e(row.classroom)}</td>
<td>${row.completed}</td><td>${row.target}</td><td>${row.submissions}</td>
<td>${e(row.averageScore.isEmpty ? '—' : row.averageScore)}</td>
<td>${row.present}</td><td>${row.attendanceTotal}</td></tr>''',
            )
            .join();
  return '''<!doctype html><html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Laporan perkembangan siswa</title><style>
*{box-sizing:border-box}body{font:12px Arial,sans-serif;color:#203438;margin:0;background:#f2f5f4}
main{max-width:1100px;margin:24px auto;background:white;padding:28px;border-radius:14px}
h1{margin:0;color:#17665b;font-size:24px}.meta{margin:7px 0 22px;color:#62716f;line-height:1.5}
button{border:0;border-radius:9px;background:#17665b;color:white;padding:12px 18px;margin-bottom:20px;cursor:pointer}
table{width:100%;border-collapse:collapse}th{background:#17665b;color:white;text-align:left}
th,td{padding:10px 8px;border:1px solid #d9e2df;vertical-align:top}tr:nth-child(even){background:#f7faf9}
.empty{text-align:center;padding:30px}.foot{margin-top:18px;color:#62716f;font-size:10px}
@page{size:A4 landscape;margin:12mm}@media print{body{background:white}main{margin:0;padding:0;max-width:none;border-radius:0}.no-print{display:none}*{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style></head><body><main><div class="no-print"><button onclick="window.print()">Unduh / Simpan PDF</button></div>
<h1>Laporan Perkembangan Siswa</h1><div class="meta"><strong>${e(school)}</strong><br>Dibuat pada ${e(generatedAt)}</div>
<table><thead><tr><th>Nama</th><th>Kelas</th><th>Hafalan tuntas</th><th>Target</th><th>Tugas</th><th>Rata-rata</th><th>Hadir</th><th>Presensi</th></tr></thead><tbody>$body</tbody></table>
<div class="foot">Dokumen dibuat melalui aplikasi E-Learning.</div></main></body></html>''';
}
