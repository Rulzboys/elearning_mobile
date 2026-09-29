import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';
import '../config/app_config.dart';
import 'repository.dart';
import '../../features/spp/spp_data.dart';

class SupabaseRepository implements LearningRepository {
  static bool _initialized = false;
  SupabaseClient get client => Supabase.instance.client;
  @override
  Future<void> initialize() async {
    if (!_initialized) {
      await Supabase.initialize(url: AppConfig.url, anonKey: AppConfig.anonKey);
      _initialized = true;
    }
  }

  @override
  Future<String?> restoreUserId() async => client.auth.currentUser?.id;
  @override
  Future<String> login(String email, String password) async {
    final r = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return r.user!.id;
  }

  @override
  Future<void> logout() => client.auth.signOut(scope: SignOutScope.local);
  @override
  Future<Snapshot> load() async {
    // RLS scopes every page. Pagination avoids silently dropping rows at 1,000.
    Future<List<Json>> all(String table) async {
      final result = <Json>[];
      for (var offset = 0; ; offset += 500) {
        final rows = await client
            .from(table)
            .select()
            .order('id')
            .range(offset, offset + 499);
        result.addAll(rows.map((e) => Json.from(e)));
        if (rows.length < 500) break;
      }
      return result;
    }

    final data = await Future.wait([
      all('profiles'),
      all('tenants'),
      all('learning_entities'),
      all('spp_qris_settings'),
      all('spp_invoices'),
      all('spp_payments'),
      all('subscription_settings'),
      all('subscription_orders'),
    ]);
    return Snapshot(
      data[0].map(AppUser.fromJson).toList(),
      data[1].map(Tenant.fromJson).toList(),
      [
        ...data[2].map(Entity.fromJson),
        ...data[3].map((r) => billingEntity(r, 'qris_setting')),
        ...data[4].map((r) => billingEntity(r, 'spp_invoice')),
        ...data[5].map((r) => billingEntity(r, 'spp_payment')),
        ...data[6].map(
          (r) => Entity(
            id: r['id'].toString(),
            tenantId: '',
            kind: 'subscription_setting',
            data: Json.from(r),
            createdAt: DateTime.parse(r['updated_at'] as String),
          ),
        ),
        ...data[7].map((r) => billingEntity(r, 'subscription_order')),
      ],
    );
  }

  @override
  Future<Json> subscriptionAction(String action, Json data) async {
    final result = await client.rpc(
      'subscription_action',
      params: {'p_action': action, 'p_data': data},
    );
    return Json.from(result as Map);
  }

  @override
  Future<Json> subscriptionCheckout(String plan) async {
    // Edge Function membuat pesanan (lewat RPC subscription_action) sekaligus
    // transaksi di payment gateway, lalu mengembalikan checkout_url.
    return _payment(AppConfig.fnCreatePayment, {
      'id': newId(),
      'plan': plan,
      'return_url': AppConfig.paymentReturnUrl,
    });
  }

  @override
  Future<Json> subscriptionPaymentStatus(
    String orderId, {
    bool force = false,
  }) => _payment(AppConfig.fnPaymentStatus, {
    'order_id': orderId,
    'force': force,
  });

  Future<Json> _payment(String function, Json body) async {
    try {
      final r = await client.functions.invoke(function, body: body);
      final data = r.data;
      if (data is! Map) {
        throw const AppFailure(
          'Layanan pembayaran tidak merespons dengan benar.',
        );
      }
      if (data['ok'] != true || data['order'] is! Map) {
        throw AppFailure(
          data['error']?.toString() ?? 'Pembayaran tidak dapat diproses.',
        );
      }
      return Json.from(data['order'] as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      throw AppFailure(
        details is Map && details['error'] != null
            ? details['error'].toString()
            : 'Layanan pembayaran tidak dapat dihubungi.',
      );
    }
  }

  @override
  Future<Json> billingAction(String action, Json data) async {
    final result = action == 'invoice_bulk'
        ? await client.rpc('spp_invoice_bulk', params: {'p_data': data})
        : action == 'report'
        ? await client.rpc('spp_report_payment', params: {'p_data': data})
        : action == 'approve'
        ? await client.rpc('spp_approve_payment', params: {'p_id': data['id']})
        : await client.rpc(
            'spp_action',
            params: {'p_action': action, 'p_data': data},
          );
    return Json.from(result as Map);
  }

  @override
  Future<String> uploadPaymentProof({
    required String tenantId,
    required String paymentId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = '$tenantId/$paymentId/proof';
    await client.storage
        .from('spp-proofs')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: 'no-store',
            upsert: true,
            contentType: contentType,
          ),
        );
    return path;
  }

  @override
  Future<String> saveStudentPhoto({
    required String tenantId,
    required String studentId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = '$tenantId/$studentId/photo';
    await client.storage
        .from('student-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: contentType,
          ),
        );
    await client.rpc(
      'set_student_photo',
      params: {'p_student_id': studentId, 'p_path': path},
    );
    return path;
  }

  @override
  Future<String> saveProfilePhoto({
    required String tenantId,
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final current = client.auth.currentUser;
    if (current == null || current.id != userId) {
      throw const AppFailure(
        'Foto profil hanya dapat diubah oleh pemilik akun.',
      );
    }
    final path = '$tenantId/$userId/photo';
    await client.storage
        .from('student-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: contentType,
          ),
        );
    await client.rpc('set_profile_photo', params: {'p_path': path});
    return path;
  }

  @override
  Future<Uint8List?> downloadPrivateFile(String bucket, String path) async {
    if (path.isEmpty) return null;
    return client.storage.from(bucket).download(path);
  }

  @override
  Future<void> saveEntity(Entity e) async {
    await client.rpc('save_learning_entity', params: {'p_entity': e.toJson()});
  }

  @override
  Future<void> deleteEntity(String id) async {
    await client.rpc('delete_learning_entity', params: {'p_id': id});
  }

  @override
  Future<void> saveTenant(Tenant t) async {
    await client.rpc('save_tenant', params: {'p_tenant': t.toJson()});
  }

  @override
  Future<void> saveUser(AppUser u, {String? password}) async {
    await _manage({
      'action': 'save',
      'user': u.toJson(),
      if (password != null && password.isNotEmpty) 'password': password,
    });
  }

  @override
  Future<void> deleteUser(String id) => _manage({'action': 'delete', 'id': id});
  Future<void> _manage(Json body) async {
    final r = await client.functions.invoke('manage-user', body: body);
    if (r.status != 200 || r.data is! Map || r.data['ok'] != true) {
      throw AppFailure(
        r.data is Map
            ? (r.data['error']?.toString() ?? 'Akun belum tersimpan.')
            : 'Akun belum tersimpan.',
      );
    }
  }

  @override
  Future<void> updateSelf(String name, String phone) async {
    await client.rpc('update_self', params: {'p_name': name, 'p_phone': phone});
  }

  @override
  Future<void> changePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> resetPassword(String email) => client.auth.resetPasswordForEmail(
    email.trim(),
    redirectTo: 'id.rulz.elearning://login-callback',
  );
  @override
  Future<QrTicket> issueQr() async {
    final r = await client.rpc('issue_student_qr');
    return QrTicket(
      r['value'] as String,
      DateTime.parse(r['expires_at'] as String),
    );
  }

  @override
  Future<String> resolveQr(String value) async =>
      await client.rpc('resolve_student_qr', params: {'p_value': value})
          as String;
}
