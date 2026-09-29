import 'dart:convert';

String studentCardDocument({
  required String name,
  required String school,
  required String number,
  required String classroom,
  required String qrPng,
  String? photoPng,
}) {
  const escape = HtmlEscape();
  String e(String v) => escape.convert(v);
  final initials = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();
  final photo = photoPng == null
      ? '<div class="photo-placeholder">${e(initials.isEmpty ? 'S' : initials)}</div>'
      : '<img class="photo" src="data:image/png;base64,$photoPng" alt="Foto siswa">';
  return '''<!doctype html>
<html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kartu siswa - ${e(name)}</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f1f4f3;font:14px Arial,sans-serif;color:#203438}
main{max-width:640px;margin:32px auto;padding:20px}h1{font-size:23px;margin:0 0 12px}
.help{line-height:1.6;color:#5a6a6d;margin-bottom:22px}button{background:#17665b;color:white;border:0;border-radius:8px;padding:14px 22px;font-size:15px;cursor:pointer;margin-bottom:24px}
.card{background:white;border:1px solid #b9c9c4;border-radius:12px;overflow:hidden;width:85mm;min-height:145mm;max-width:100%;break-inside:avoid;margin-inline:auto}
.head{padding:18px 20px;border-bottom:3px solid #17665b}.brand{font-weight:bold;letter-spacing:2px;font-size:11px;color:#17665b}.school{margin-top:8px;font-size:14px;line-height:1.4}
.body{text-align:center;padding:18px 20px}.label{font-size:10px;letter-spacing:2px;color:#657873}.name{font-size:20px;line-height:1.3;margin:12px 0 7px;overflow-wrap:anywhere}.meta{font-size:12px;line-height:1.6;color:#526661}
.photo,.photo-placeholder{display:flex;width:24mm;height:24mm;margin:14px auto 10px;border-radius:50%;object-fit:cover;border:2px solid #d8e7e1;background:#e7f0eb;align-items:center;justify-content:center;color:#17665b;font-size:22px;font-weight:bold}
.qr{display:block;width:47mm;height:47mm;max-width:100%;object-fit:contain;margin:14px auto;background:white;image-rendering:pixelated}
.foot{font-size:10px;line-height:1.6;border-top:1px solid #dce5e1;padding:12px 20px;text-align:center}
@page{size:A4;margin:15mm}@media print{body{background:white}main{margin:0;padding:0;max-width:none;width:180mm;min-height:266mm;display:flex;align-items:center;justify-content:center}.no-print{display:none}.card{width:85mm;max-width:none;box-shadow:none;flex-shrink:0}*{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style></head><body><main>
<div class="no-print"><h1>Kartu siswa siap dicetak</h1><p class="help">Pilih Cetak / Simpan PDF. Gunakan ukuran asli (100%) agar QR tetap jelas. Jika tombol tidak tersedia, gunakan menu Cetak pada browser. Simpan PDF untuk mencetak di perangkat lain.</p>
<button onclick="window.print()">Cetak / Simpan PDF</button></div>
<article class="card"><div class="head"><div class="brand">E-LEARNING</div><div class="school">${e(school)}</div></div>
<div class="body"><div class="label">KARTU SISWA</div>$photo<h2 class="name">${e(name)}</h2>
<div class="meta">${e(classroom)}<br>NIS: ${e(number.isEmpty ? '—' : number)}</div>
<img class="qr" src="data:image/png;base64,$qrPng" alt="QR identitas siswa">
<div class="meta">Tunjukkan kartu kepada guru untuk<br>presensi, hafalan, dan layanan siswa.</div></div>
<div class="foot">Kartu pengenal belajar · Bukan akses masuk akun<br>Simpan dengan baik dan jaga QR tetap terbaca.</div></article>
</main></body></html>''';
}
