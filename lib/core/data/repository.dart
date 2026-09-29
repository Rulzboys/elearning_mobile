import 'dart:typed_data';
import '../../shared/models/models.dart';

abstract class LearningRepository {
  Future<void> initialize();
  Future<String?> restoreUserId();
  Future<String> login(String email, String password);
  Future<void> logout();
  Future<Snapshot> load();
  Future<Json> billingAction(String action, Json data);
  Future<Json> subscriptionAction(String action, Json data);

  /// Membuat pesanan langganan sekaligus transaksi di payment gateway.
  /// Mengembalikan baris `subscription_orders` yang sudah berisi `checkout_url`.
  Future<Json> subscriptionCheckout(String plan);

  /// Memeriksa status pembayaran ke gateway lalu menyinkronkannya ke database.
  /// Mengembalikan baris pesanan terbaru (`status` sudah diperbarui).
  Future<Json> subscriptionPaymentStatus(String orderId, {bool force = false});

  Future<String> uploadPaymentProof({
    required String tenantId,
    required String paymentId,
    required Uint8List bytes,
    required String contentType,
  });
  Future<String> saveStudentPhoto({
    required String tenantId,
    required String studentId,
    required Uint8List bytes,
    required String contentType,
  });
  Future<String> saveProfilePhoto({
    required String tenantId,
    required String userId,
    required Uint8List bytes,
    required String contentType,
  });
  Future<Uint8List?> downloadPrivateFile(String bucket, String path);
  Future<void> saveEntity(Entity entity);
  Future<void> deleteEntity(String id);
  Future<void> saveTenant(Tenant tenant);
  Future<void> saveUser(AppUser user, {String? password});
  Future<void> deleteUser(String id);
  Future<void> updateSelf(String name, String phone);
  Future<void> changePassword(String password);
  Future<void> resetPassword(String email);
  Future<QrTicket> issueQr();
  Future<String> resolveQr(String value);
}
