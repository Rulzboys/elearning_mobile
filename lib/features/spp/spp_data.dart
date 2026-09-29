import 'package:intl/intl.dart';
import '../../shared/models/models.dart';

String rupiah(num value) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
).format(value);
const paymentLabels = {
  'pending': 'Menunggu pembayaran',
  'reported': 'Dilaporkan wali',
  'matched': 'Lunas • terverifikasi DANA',
  'disputed': 'Perlu klarifikasi',
};
int credited(
  Iterable<Entity> payments,
  String invoiceId, {
  bool verifiedOnly = false,
}) => payments
    .where(
      (p) =>
          p.text('invoice_id') == invoiceId &&
          (p.text('status') == 'matched' ||
              (!verifiedOnly && p.text('status') == 'reported')),
    )
    .fold(0, (sum, p) => sum + p.number('amount'));
Entity billingEntity(Json row, String kind) => Entity(
  id: row['id'] as String,
  tenantId: row['tenant_id'] as String,
  kind: kind,
  data: row,
  createdAt: DateTime.parse(row['created_at'] as String),
  authorId: row['created_by'] as String?,
);

String whatsappLink(String phone, String message) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0')) digits = '62${digits.substring(1)}';
  if (digits.length < 9 || digits.length > 15)
    throw const AppFailure('Lengkapi nomor WhatsApp wali pada profil siswa.');
  return Uri.https('wa.me', '/$digits', {'text': message}).toString();
}
