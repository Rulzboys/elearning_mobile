# Pembaruan suara scan MP3 dan menu akses cepat

## Pemasangan wajib

Ganti folder `lib` proyek dengan folder `lib` dalam ZIP ini. Tambahkan dua baris
berikut ke bagian `dependencies` pada **pubspec.yaml yang sedang Anda gunakan**:

```yaml
  audioplayers: 6.5.1
  vibration: 3.1.3
```

Jangan membuat bagian `dependencies` kedua. Pertahankan dependensi lain, termasuk
`intl: ^0.20.3` yang sudah disesuaikan dengan Flutter Anda. Paket ini tidak
menyertakan pubspec pengganti agar konfigurasi proyek Anda tetap sesuai.

Salin file `assets/sound/scan_success.mp3` dari ZIP ke lokasi yang sama pada root
proyek (sejajar dengan `lib`). ZIP menyertakan bunyi scan pendek siap pakai. Jika
Anda sudah memiliki MP3 sendiri pada lokasi tersebut, pertahankan file Anda.
Daftarkan aset pada bagian `flutter` yang sudah ada di pubspec.yaml:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/sound/scan_success.mp3
```

Gabungkan dengan daftar assets lama, jangan membuat bagian `flutter` kedua.
Kode menggunakan `AssetSource('sound/scan_success.mp3')` karena audioplayers
menambahkan awalan `assets/` otomatis. Ejaan folder adalah `sound`, bukan `sounds`.
Pemutaran memakai mode mediaPlayer dan volume 1. Pastikan volume media HP terdengar.
File `core/services/scan_tone.dart` versi lama sudah tidak digunakan dan dihapus
dari paket ini. Tidak perlu menambahkan dependensi baru jika dua paket di atas
sudah terpasang.

Plugin vibration menyertakan izin VIBRATE melalui
manifest merger Android. Bila memeriksa manifest sendiri, izin ini berada
langsung di bawah `<manifest>`, di luar `<application>`:

```xml
<uses-permission android:name="android.permission.VIBRATE" />
```

Tidak wajib mengganti seluruh AndroidManifest.xml. Pertahankan izin CAMERA dan
INTERNET yang sudah digunakan. Pada activity Flutter, gunakan
`android:windowSoftInputMode="adjustResize"` (nilai bawaan proyek Flutter).
Tidak ada perubahan env.json, SQL, migration, atau konfigurasi Supabase.

Hentikan aplikasi sepenuhnya, lalu jalankan:

```powershell
flutter pub get
flutter run --dart-define-from-file=env.json
```

Penambahan plugin native memerlukan build ulang, bukan hanya hot reload.

## Perubahan terbaru

- Suara scan sekarang berasal dari MP3 aset, bukan WAV yang dibuat saat runtime.
- Menu akses cepat difilter berdasarkan rute empat tab navigasi role aktif:
  siswa/guru tidak mengulang Jadwal dan Tugas; admin tidak mengulang Siswa dan
  Pengumuman; developer tidak menampilkan bagian Pengelolaan karena seluruh
  menunya sudah berada di navigasi bawah. Guru tetap memiliki akses cepat Siswa.
- Kartu ringkasan, agenda, pengumuman terbaru, dan tombol utama scan tetap tersedia.
- Layout form tidak lagi berganti struktur saat tinggi keyboard berubah.
  Fokus, controller, dan isian tetap berada pada widget yang sama. Dialog mengikuti
  perubahan inset keyboard tanpa memulai tween posisi berulang pada setiap frame.
- Dialog tambah/edit, hapus, logout, perubahan status instansi, dan Cetak/Simpan PDF
  menggunakan komponen `shared/widgets/app_dialog.dart` yang sama.
- Scanner hanya memiliki tombol Lampu di tengah; tombol Coba lagi dihapus.
  QR yang gagal diproses diberi pesan dan kamera mencoba memindai kembali otomatis.
- Suara MP3 dan getaran 250 ms dipanggil bersama setelah data siswa berhasil
  diperiksa. QR tidak valid/tidak berwenang tidak mendapat tanda berhasil.
  Kegagalan suara/getaran tidak menghalangi pembukaan data siswa.
- Kartu ditempatkan di tengah bidang cetak A4, baik horizontal maupun vertikal;
  QR tetap berada di tengah kartu. Transisi halaman juga diperhalus.

## Tampilan dan navigasi yang dipertahankan

Pembaruan terbaru mempertahankan tampilan halaman dari paket UI sebelumnya.
Dialog tambah/edit kini memakai judul dan label yang lebih rapi, tombol simpan
di bagian bawah, form bergulir saat keyboard terbuka, pilihan kata sandi terlihat,
serta validasi dan pesan kegagalan tanpa menghapus isian. Dialog konfirmasi hapus
juga disesuaikan. Penyimpanan ganda dan penutupan saat menyimpan dicegah.

Navigasi utama dipisahkan ke `app/navigation/main_navigation.dart`:
`MainTabs` menentukan empat tab, `MainNavigation` menjadi wadah halaman setelah
login, dan `AppBottomNavigationBar` menampilkan tab aktif. `app/router.dart`
memasang wadah tersebut melalui ShellRoute.

Empat tab siswa/guru: Beranda, Jadwal, Tugas, Profil.
Empat tab admin: Beranda, Siswa, Pengumuman, Profil.
Empat tab developer: Beranda, Instansi, Admin, Profil.

Navigasi tampil pada keempat halaman utama sesuai role, termasuk jika halaman
tersebut dibuka melalui menu beranda. Halaman scanner, kartu, detail siswa, dan
fitur lain di luar empat tab tampil penuh tanpa navigasi bawah. Kembali dari
detail mengembalikan tab asal. Pindah tab memakai penggantian lokasi, sehingga
tidak menumpuk halaman tab. Filter lokal halaman dapat kembali ke awal ketika
tab dibuka ulang; penyimpanan state setiap tab tidak ditambahkan pada paket ini.

## Perubahan

- Tema pendidikan hijau tua, warna netral, tipografi, kartu, formulir, dan menu
  beranda yang diperbarui. Halaman profil dan login ikut disesuaikan.
- Navigasi bawah muncul pada empat halaman tab utama setiap role. Detail dibuka
  sebagai halaman tersendiri dengan tombol kembali. Tombol kembali Android didukung.
- Scanner kamera memenuhi halaman; input kode manual dihapus. Tersedia lampu dan
  penanganan izin kamera. Kamera berhenti ketika membuka
  catatan siswa atau aplikasi berada di latar belakang.
- Kartu QR siswa tetap dapat dicetak, tanpa batas kedaluwarsa lima menit.
- Admin/guru: buka menu Siswa, tekan menu titik tiga siswa, pilih Kartu QR siswa.
  Kartu juga tersedia melalui ikon kartu di halaman hafalan siswa.
- Siswa: buka Kartu siswa dari beranda.

## Mencetak kartu

Pilih Cetak / Simpan PDF, lalu Buka kartu. Browser pada perangkat yang sama
menampilkan kartu; pilih Cetak / Simpan PDF atau gunakan menu Cetak browser.
Hasil PDF dapat dikirim ke komputer/tempat cetak. Ukuran kartu sekitar 85 x 125 mm;
gunakan kertas A4 portrait, skala 100%, dan pastikan QR tercetak utuh. Matikan
header/footer browser pada pengaturan cetak agar URL/tanggal tidak ikut tercetak.

Biarkan aplikasi hidup di latar belakang sampai halaman kartu selesai dimuat.
Tautan sementara hanya berlaku pada perangkat yang membuatnya. Jika sistem
menutup aplikasi, buka kembali kartu dan siapkan halaman cetak yang baru.
Jika browser tidak berhasil dibuka otomatis, tautan disalin ke clipboard agar
bisa ditempel pada kolom alamat browser perangkat yang sama.

Pembukaan browser memakai url_launcher yang sudah menjadi dependensi
supabase_flutter 2.10.0 pada proyek ini. Dua paket baru di atas dipakai untuk suara
dan getaran scanner. Jika mengganti/menghapus supabase_flutter kelak,
daftarkan url_launcher secara langsung di pubspec.

## Cara kerja dan akses

Format baru ELRNCARD1 berisi ID instansi dan ID siswa. Ini pengenal untuk mencari
profil, bukan password, token login, atau bukti kehadiran. Tidak ada nilai hafalan
atau kredensial di dalam QR. QR cetak bisa disalin seperti kartu identitas lain;
guru perlu mencocokkan siswa dengan nama yang tampil sebelum mencatat setoran.

Saat scan, data dimuat ulang melalui koneksi Supabase yang terautentikasi dan RLS
yang sudah ada. Status akun, instansi, dan kelas bimbingan diperiksa kembali. Guru
perlu internet; siswa cukup membawa kartu cetak. Semua perangkat guru yang akan
memindai kartu baru perlu memakai versi aplikasi yang diperbarui ini. QR sementara
ELRN1 dari aplikasi lama masih didukung selama tiketnya belum kedaluwarsa.

Menonaktifkan siswa/instansi membuat kartu tidak dapat digunakan untuk membuka
data. Pencabutan satu kartu saja tanpa menonaktifkan akun membutuhkan fitur token
kartu pada database; pembaruan lib ini tidak menambahkan mekanisme tersebut.

Halaman cetak Android disajikan hanya pada loopback perangkat, dengan alamat
acak dan tanpa cache browser. Tidak ada unggahan data kartu ke layanan cetak luar.
Flutter Web memakai halaman Blob pada browser (build web JavaScript).

Referensi implementasi: [Dart HttpServer.bind](https://api.dart.dev/dart-io/HttpServer/bind.html)
dan [QrPainter](https://pub.dev/documentation/qr_flutter/4.1.0/qr_flutter/QrPainter-class.html).

## Validasi

- Dart analyze: tidak ada masalah.
- Pembaruan ini: 10 pengujian terarah lolos (dua pengujian suara/getaran dan
  delapan pengujian kartu/navigasi). Aset MP3 dimuat dari bundle, diteruskan ke
  pemutar, dan byte file yang diputar dicocokkan dengan MP3 sumber. Pemeriksaan
  menu dilakukan untuk empat role. MP3 juga berhasil didekode dan tidak hening.
- Pada versi sebelumnya, 30 pengujian otomatis lolos, termasuk
  fokus/isian saat inset keyboard berubah, pemanggilan suara/getaran,
  kegagalan vibrator, posisi tombol Lampu, navigasi empat role, dan dialog cetak/logout.
- Render dialog form, logout, dan cetak ditinjau pada ukuran layar 390 x 844.
- Pengujian meliputi alur lama, kartu tetap, pembatasan role/kelas/akun nonaktif,
  empat tab utama dan detail, scanner tanpa input manual, halaman pada layar kecil,
  render form, validasi wajib isi, pengiriman data, mencoba ulang saat gagal,
  keyboard, pilihan dropdown, kata sandi, dan pencegahan penyimpanan ganda.
- 7 pemeriksaan layanan kartu lolos: format QR, payload tidak valid, escape HTML,
  halaman cetak lokal, header tanpa cache, dan penolakan path lain.
- Pengujian menggunakan Flutter 3.35.7 / Dart 3.9.2 dan mode demo untuk alur UI.
  Kamera, speaker, vibrator fisik, pencetakan melalui Chrome Android/printer, dan backend Supabase
  milik pengguna belum diuji langsung. Build APK tidak dilakukan di lingkungan ini.
- Kelancaran aktual perlu diperiksa pada HP. Untuk mengukur interaksi tanpa beban
  mode debug, gunakan `flutter run --profile --dart-define-from-file=env.json`.
