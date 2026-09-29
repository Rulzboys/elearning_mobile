import '../../shared/models/models.dart';
import 'qris_payload.dart';

/// Local-only simulation. Production authorization and state transitions live in PostgreSQL.
class DemoBilling {
  static Json apply(
    AppUser a,
    Snapshot snapshot,
    List<Json> rows,
    String action,
    Json d,
  ) {
    final tenant = snapshot.tenants
        .where((t) => t.id == a.tenantId)
        .firstOrNull;
    if (!a.active ||
        tenant?.isActive != true ||
        !(a.role.managesSchool || a.role == UserRole.student)) {
      throw const AppFailure('Akses SPP ditolak.');
    }
    final now = DateTime.now().toUtc();
    final stamp = now.toIso8601String();
    final own = rows.where((r) => r['tenant_id'] == a.tenantId).toList();
    final id = d['id']?.toString() ?? newId();
    Json? find(String ident) => rows.where((r) => r['id'] == ident).firstOrNull;
    Json result;
    var kind = '';
    void manager() {
      if (!a.role.managesSchool) {
        throw const AppFailure(
          'Hanya Admin dan Pimpinan boleh mengelola SPP/QRIS.',
        );
      }
    }

    int used(String invoiceId, [String? except]) => own
        .where(
          (r) =>
              r['kind'] == 'spp_payment' &&
              r['invoice_id'] == invoiceId &&
              r['id'] != except &&
              ['reported', 'matched'].contains(r['status']),
        )
        .fold(0, (sum, r) => sum + (r['amount'] as int));
    switch (action) {
      case 'settings':
        manager();
        kind = 'qris_setting';
        final payload = d['payload']?.toString().trim() ?? '';
        final name = QrisPayload.validateStatic(payload);
        if (d['consent'] != true) {
          throw const AppFailure('Konfirmasi izin merchant terlebih dahulu.');
        }
        final old = own.where((r) => r['kind'] == kind).firstOrNull;
        result = {
          ...?old,
          'id': old?['id'] ?? id,
          'payload': payload,
          'merchant_name': name,
          'enabled': d['enabled'] == true,
          'nominal_enabled': d['nominal_enabled'] == true,
          'contact_phone': d['contact_phone'] ?? '',
          'updated_at': stamp,
        };
      case 'invoice':
        manager();
        kind = 'spp_invoice';
        final old = find(id);
        if (old != null &&
            (old['tenant_id'] != a.tenantId ||
                old['student_id'] != d['student_id'])) {
          throw const AppFailure('Tagihan tidak sesuai.');
        }
        if (own.any((r) => r['invoice_id'] == id)) {
          throw const AppFailure('Tagihan memiliki transaksi. Gunakan arsip.');
        }
        if (!snapshot.users.any(
          (u) =>
              u.id == d['student_id'] &&
              u.tenantId == a.tenantId &&
              u.role == UserRole.student &&
              u.active,
        )) {
          throw const AppFailure('Pilih siswa aktif.');
        }
        final amount = d['amount'];
        if (amount is! int ||
            amount < 1 ||
            amount > 1000000000 ||
            (d['title']?.toString().trim() ?? '').isEmpty ||
            (d['period']?.toString().trim() ?? '').isEmpty ||
            DateTime.tryParse(d['due_date']?.toString() ?? '') == null) {
          throw const AppFailure('Lengkapi tagihan dan nominal yang valid.');
        }
        if (own.any(
          (r) =>
              r['kind'] == kind &&
              r['id'] != id &&
              r['student_id'] == d['student_id'] &&
              r['title'] == d['title'] &&
              r['period'] == d['period'],
        )) {
          throw const AppFailure('Tagihan sudah ada.');
        }
        result = {
          ...?old,
          'id': id,
          'student_id': d['student_id'],
          'title': d['title'],
          'period': d['period'],
          'amount': amount,
          'due_date': d['due_date'],
          'allow_partial': d['allow_partial'] == true,
          'archived': false,
        };
      case 'invoice_bulk':
        manager();
        if (d['scope'] != 'all') {
          throw const AppFailure('Pilihan penerima tagihan tidak valid.');
        }
        final amount = d['amount'];
        if (amount is! int ||
            amount < 1 ||
            amount > 1000000000 ||
            (d['title']?.toString().trim() ?? '').isEmpty ||
            (d['period']?.toString().trim() ?? '').isEmpty ||
            DateTime.tryParse(d['due_date']?.toString() ?? '') == null) {
          throw const AppFailure('Lengkapi tagihan dan nominal yang valid.');
        }
        final students = snapshot.users.where(
          (u) =>
              u.tenantId == a.tenantId &&
              u.role == UserRole.student &&
              u.active,
        );
        if (students.isEmpty) {
          throw const AppFailure('Belum ada siswa / santri aktif.');
        }
        var created = 0, skipped = 0;
        for (final student in students) {
          final duplicate = own.any(
            (r) =>
                r['kind'] == 'spp_invoice' &&
                r['student_id'] == student.id &&
                r['title'] == d['title'] &&
                r['period'] == d['period'],
          );
          if (duplicate) {
            skipped++;
            continue;
          }
          rows.add({
            'id': newId(),
            'tenant_id': a.tenantId,
            'student_id': student.id,
            'title': d['title'],
            'period': d['period'],
            'amount': amount,
            'due_date': d['due_date'],
            'allow_partial': d['allow_partial'] == true,
            'archived': false,
            'created_at': stamp,
            'created_by': a.id,
            'kind': 'spp_invoice',
          });
          created++;
        }
        return {
          'scope': 'all',
          'created_count': created,
          'skipped_count': skipped,
          'total_count': created + skipped,
        };
      case 'archive':
        manager();
        kind = 'spp_invoice';
        final old = find(id);
        if (old == null ||
            old['tenant_id'] != a.tenantId ||
            old['kind'] != kind) {
          throw const AppFailure('Tagihan tidak ditemukan.');
        }
        result = {...old, 'archived': old['archived'] != true};
      case 'checkout':
        if (a.role != UserRole.student) {
          throw const AppFailure('Checkout hanya untuk wali/siswa.');
        }
        kind = 'spp_payment';
        final old = find(id);
        if (old != null) {
          if (old['student_id'] != a.id ||
              old['invoice_id'] != d['invoice_id'] ||
              old['amount'] != d['amount']) {
            throw const AppFailure('ID sudah digunakan.');
          }
          return old;
        }
        final invoice = own
            .where(
              (r) =>
                  r['id'] == d['invoice_id'] &&
                  r['kind'] == 'spp_invoice' &&
                  r['student_id'] == a.id &&
                  r['archived'] != true,
            )
            .firstOrNull;
        if (invoice == null) throw const AppFailure('Tagihan tidak tersedia.');
        final amount = d['amount'];
        final remaining =
            (invoice['amount'] as int) - used(invoice['id'] as String);
        if (amount is! int ||
            amount < 1 ||
            amount > 10000000 ||
            amount > remaining ||
            (invoice['allow_partial'] != true && amount != remaining)) {
          throw const AppFailure(
            'Nominal tidak sesuai sisa tagihan atau aturan cicilan.',
          );
        }
        final active = own
            .where(
              (r) =>
                  r['invoice_id'] == invoice['id'] &&
                  r['status'] == 'pending' &&
                  DateTime.parse(r['expires_at'] as String).isAfter(now),
            )
            .firstOrNull;
        if (active != null) {
          if (active['amount'] == amount) return active;
          throw const AppFailure('Masih ada sesi QR aktif. Buka dari riwayat.');
        }
        final settings = own
            .where((r) => r['kind'] == 'qris_setting' && r['enabled'] == true)
            .firstOrNull;
        if (settings == null) {
          throw const AppFailure('QRIS belum diaktifkan pengelola.');
        }
        final raw = settings['payload'] as String;
        result = {
          'id': id,
          'invoice_id': invoice['id'],
          'student_id': a.id,
          'amount': amount,
          'status': 'pending',
          'payload': settings['nominal_enabled'] == true
              ? QrisPayload.withAmount(raw, amount)
              : raw,
          'merchant_name': settings['merchant_name'],
          'contact_phone': settings['contact_phone'],
          'expires_at': now.add(const Duration(minutes: 5)).toIso8601String(),
        };
      case 'report':
      case 'approve':
      case 'reconcile':
        kind = 'spp_payment';
        final old = find(id);
        if (old == null ||
            old['tenant_id'] != a.tenantId ||
            old['kind'] != kind) {
          throw const AppFailure('Transaksi tidak ditemukan.');
        }
        if (action == 'report') {
          if (a.role != UserRole.student || old['student_id'] != a.id) {
            throw const AppFailure('Transaksi bukan milik Anda.');
          }
          if (['reported', 'matched'].contains(old['status'])) return old;
          if (old['status'] != 'pending') {
            throw const AppFailure('Hubungi pengelola untuk klarifikasi.');
          }
          if ((d['payer_name']?.toString().trim() ?? '').isEmpty ||
              !(d['proof_path']?.toString() ?? '').startsWith('data:image/')) {
            throw const AppFailure(
              'Nama pembayar dan bukti pembayaran wajib diisi.',
            );
          }
          result = {
            ...old,
            'status': 'reported',
            'payer_name': d['payer_name'],
            'transfer_reference': '',
            'proof_path': d['proof_path'],
            'reported_at': stamp,
            'reported_late': now.isAfter(
              DateTime.parse(old['expires_at'] as String),
            ),
          };
        } else if (action == 'approve') {
          manager();
          if (old['status'] != 'reported') {
            throw const AppFailure(
              'Hanya bukti pembayaran yang menunggu persetujuan yang dapat disetujui.',
            );
          }
          result = {
            ...old,
            'status': 'matched',
            'review_note': 'Bukti pembayaran disetujui pengelola.',
            'reviewed_at': stamp,
            'reviewed_by': a.id,
          };
        } else {
          manager();
          if (!['matched', 'disputed'].contains(d['status']) ||
              (d['review_note']?.toString().trim() ?? '').isEmpty) {
            throw const AppFailure('Hasil pengecekan dan catatan wajib diisi.');
          }
          final bankRef = d['bank_reference']?.toString().trim() ?? '';
          if (d['status'] == 'matched' &&
              (bankRef.isEmpty ||
                  own.any(
                    (r) =>
                        r['id'] != id &&
                        r['status'] == 'matched' &&
                        r['bank_reference'] == bankRef,
                  ))) {
            throw const AppFailure(
              'Referensi mutasi wajib diisi dan tidak boleh digunakan dua kali.',
            );
          }
          result = {
            ...old,
            'status': d['status'],
            'review_note': d['review_note'],
            'bank_reference': d['status'] == 'matched' ? bankRef : null,
            'reviewed_at': stamp,
            'reviewed_by': a.id,
          };
        }
        if (['reported', 'matched'].contains(result['status'])) {
          final invoice = find(old['invoice_id'] as String)!;
          if (used(invoice['id'] as String, id) + (old['amount'] as int) >
              (invoice['amount'] as int)) {
            throw const AppFailure(
              'Total melebihi tagihan. Hubungi pengelola.',
            );
          }
        }
      default:
        throw const AppFailure('Aksi tidak dikenal.');
    }
    result = {
      'tenant_id': a.tenantId,
      'created_at': stamp,
      'created_by': a.id,
      ...result,
      'kind': kind,
    };
    rows.removeWhere((r) => r['id'] == result['id']);
    rows.add(result);
    return result;
  }
}
