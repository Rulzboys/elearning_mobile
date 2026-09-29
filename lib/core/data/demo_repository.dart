import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/models.dart';
import 'demo_seed.dart';
import 'repository.dart';
import '../../features/spp/demo_billing.dart';
import '../../features/spp/spp_data.dart';

/// Local demonstration only. Cloud authorization lives in PostgreSQL RLS/RPCs.
class DemoRepository implements LearningRepository {
  static const storageKey = 'elearning_demo_v1';

  /// Berapa lama pembayaran demo "diproses" sebelum dianggap lunas.
  static const demoSettlementDelay = Duration(seconds: 6);

  late SharedPreferences prefs;
  late Json db;
  String? _uid;
  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  @override
  Future<void> initialize() async {
    prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        db = Json.from(jsonDecode(raw) as Map);
      } catch (_) {
        throw const AppFailure(
          'Data demo tidak dapat dibaca. Hapus data aplikasi untuk memulai ulang.',
        );
      }
    } else {
      final s = DemoSeed.create();
      db = {
        'users': s.users.map((x) => x.toJson()).toList(),
        'tenants': s.tenants.map((x) => x.toJson()).toList(),
        'entities': s.entities.map((x) => x.toJson()).toList(),
        'tickets': <String, dynamic>{},
        'passwords': {
          for (final u in s.users) u.id: _hash(DemoSeed.password, u.id),
        },
      };
      if (!await prefs.setString(storageKey, jsonEncode(db))) {
        throw const AppFailure('Penyimpanan perangkat tidak tersedia.');
      }
    }
    _uid = prefs.getString('elearning_demo_session');
    db.putIfAbsent('billing', () => <Json>[]);
    db.putIfAbsent(
      'subscriptions',
      () => <Json>[
        {
          'id': '00000000-0000-4000-8000-000000000001',
          'kind': 'subscription_setting',
          'monthly_price': 10000,
          'annual_price': 100000,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    );
    // Upgrade existing local demos without resetting user data.
    if (!_rows('users').any((u) => u['role'] == 'leader')) {
      final leader = DemoSeed.create().users.firstWhere(
        (u) => u.role == UserRole.leader,
      );
      db['users'] = [..._rows('users'), leader.toJson()];
      db['passwords'][leader.id] = _hash(DemoSeed.password, leader.id);
      await prefs.setString(storageKey, jsonEncode(db));
    }
  }

  Future<void> _commit(void Function() apply) async {
    final before = jsonEncode(db);
    try {
      apply();
      if (!await prefs.setString(storageKey, jsonEncode(db))) {
        throw const AppFailure('Perubahan belum tersimpan. Coba lagi.');
      }
    } catch (_) {
      db = Json.from(jsonDecode(before) as Map);
      rethrow;
    }
  }

  List<Json> _rows(String key) =>
      (db[key] as List).map((e) => Json.from(e as Map)).toList();
  AppUser get actor => AppUser.fromJson(
    _rows('users').firstWhere(
      (u) => u['id'] == _uid,
      orElse: () => throw const AppFailure('Silakan masuk kembali.'),
    ),
  );
  @override
  Future<String?> restoreUserId() async => _uid;
  @override
  Future<String> login(String email, String password) async {
    final matches = _rows('users').where(
      (u) => u['email'].toString().toLowerCase() == email.trim().toLowerCase(),
    );
    if (matches.isEmpty ||
        db['passwords'][matches.first['id']] !=
            _hash(password, matches.first['id'] as String)) {
      throw const AppFailure('Email atau kata sandi tidak sesuai.');
    }
    final id = matches.first['id'] as String;
    if (!await prefs.setString('elearning_demo_session', id)) {
      throw const AppFailure('Sesi tidak dapat disimpan.');
    }
    _uid = id;
    return id;
  }

  @override
  Future<void> logout() async {
    await prefs.remove('elearning_demo_session');
    _uid = null;
  }

  @override
  Future<Snapshot> load() async => Snapshot(
    _rows('users').map(AppUser.fromJson).toList(),
    _rows('tenants').map(Tenant.fromJson).toList(),
    [
      ..._rows('entities').map(Entity.fromJson),
      ..._rows('billing').map((r) => billingEntity(r, r['kind'] as String)),
      ..._rows('subscriptions').map(
        (r) => r['kind'] == 'subscription_order'
            ? billingEntity(r, 'subscription_order')
            : Entity(
                id: r['id'] as String,
                tenantId: '',
                kind: 'subscription_setting',
                data: r,
                createdAt: DateTime.parse(r['updated_at'] as String),
              ),
      ),
    ],
  );
  @override
  Future<Json> billingAction(String action, Json data) async {
    late Json result;
    final snapshot = await load();
    await _commit(() {
      final rows = _rows('billing');
      result = DemoBilling.apply(actor, snapshot, rows, action, data);
      db['billing'] = rows;
    });
    return result;
  }

  @override
  Future<Json> subscriptionAction(String action, Json data) async {
    late Json result;
    await _commit(() {
      final rows = _rows('subscriptions');
      if (action == 'settings') {
        if (actor.role != UserRole.developer) {
          throw const AppFailure('Hanya Developer yang dapat mengatur harga.');
        }
        final monthly = (data['monthly_price'] as num?)?.toInt() ?? 0;
        final annual = (data['annual_price'] as num?)?.toInt() ?? 0;
        if (monthly < 1000 || annual < 1000) {
          throw const AppFailure('Harga langganan belum valid.');
        }
        result = {
          'id': '00000000-0000-4000-8000-000000000001',
          'kind': 'subscription_setting',
          'monthly_price': monthly,
          'annual_price': annual,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        rows.removeWhere((e) => e['kind'] == 'subscription_setting');
        rows.add(result);
      } else if (action == 'create') {
        if (actor.role != UserRole.student || actor.tenantId == null) {
          throw const AppFailure(
            'Pembayaran langganan hanya melalui akun siswa.',
          );
        }
        final setting =
            rows
                .where((e) => e['kind'] == 'subscription_setting')
                .firstOrNull ??
            {'monthly_price': 10000, 'annual_price': 100000};
        final plan = data['plan']?.toString();
        if (!['monthly', 'annual'].contains(plan)) {
          throw const AppFailure('Paket langganan tidak valid.');
        }
        result = {
          'id': data['id'] ?? newId(),
          'kind': 'subscription_order',
          'tenant_id': actor.tenantId,
          'buyer_id': actor.id,
          'plan': plan,
          'amount': plan == 'annual'
              ? setting['annual_price']
              : setting['monthly_price'],
          'regular_price': plan == 'annual'
              ? (setting['monthly_price'] as int) * 12
              : setting['monthly_price'],
          'status': 'pending',
          'checkout_url': '',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        rows.add(result);
      } else {
        throw const AppFailure('Aksi langganan tidak dikenal.');
      }
      db['subscriptions'] = rows;
    });
    return result;
  }

  @override
  Future<Json> subscriptionCheckout(String plan) async {
    final order = await subscriptionAction('create', {
      'id': newId(),
      'plan': plan,
    });
    late Json result;
    await _commit(() {
      final rows = _rows('subscriptions');
      final index = rows.indexWhere((e) => e['id'] == order['id']);
      if (index < 0) throw const AppFailure('Pesanan tidak ditemukan.');
      final now = DateTime.now().toUtc();
      result = {
        ...rows[index],
        'gateway': 'demo',
        'gateway_env': 'demo',
        'gateway_reference': 'DEMO-${now.millisecondsSinceEpoch}',
        // URL simulasi: tidak memanggil gateway mana pun.
        'checkout_url':
            'https://example.invalid/demo-checkout?ref=${order['id']}',
        'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
      };
      rows[index] = result;
      db['subscriptions'] = rows;
    });
    return result;
  }

  @override
  Future<Json> subscriptionPaymentStatus(
    String orderId, {
    bool force = false,
  }) async {
    late Json result;
    await _commit(() {
      final rows = _rows('subscriptions');
      final index = rows.indexWhere(
        (e) => e['kind'] == 'subscription_order' && e['id'] == orderId,
      );
      if (index < 0) throw const AppFailure('Transaksi tidak ditemukan.');
      final row = rows[index];
      if (row['buyer_id'] != actor.id && actor.role != UserRole.developer) {
        throw const AppFailure('Transaksi tidak dapat diakses dari akun ini.');
      }
      if (row['status'] != 'pending') {
        result = row;
        return;
      }
      final created = DateTime.parse(row['created_at'] as String);
      final settled =
          force ||
          DateTime.now().toUtc().difference(created) >= demoSettlementDelay;
      result = settled
          ? {
              ...row,
              'status': 'paid',
              'gateway_status': 'DEMO_SUCCESS',
              'paid_at': DateTime.now().toUtc().toIso8601String(),
            }
          : row;
      rows[index] = result;
      db['subscriptions'] = rows;
    });
    return result;
  }

  String _dataUrl(String contentType, Uint8List bytes) =>
      'data:$contentType;base64,${base64Encode(bytes)}';

  @override
  Future<String> uploadPaymentProof({
    required String tenantId,
    required String paymentId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (actor.tenantId != tenantId || actor.role != UserRole.student) {
      throw const AppFailure('Bukti pembayaran tidak dapat disimpan.');
    }
    return _dataUrl(contentType, bytes);
  }

  @override
  Future<String> saveStudentPhoto({
    required String tenantId,
    required String studentId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!actor.role.managesSchool || actor.tenantId != tenantId) {
      throw const AppFailure('Foto siswa hanya dapat diubah pengelola.');
    }
    final path = _dataUrl(contentType, bytes);
    await _commit(() {
      final users = _rows('users');
      final index = users.indexWhere(
        (u) =>
            u['id'] == studentId &&
            u['tenant_id'] == tenantId &&
            u['role'] == 'student',
      );
      if (index < 0) throw const AppFailure('Siswa tidak ditemukan.');
      users[index] = {...users[index], 'photo_path': path};
      db['users'] = users;
    });
    return path;
  }

  @override
  Future<String> saveProfilePhoto({
    required String tenantId,
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final scope = actor.tenantId ?? 'platform';
    if (actor.id != userId || scope != tenantId) {
      throw const AppFailure(
        'Foto profil hanya dapat diubah oleh pemilik akun.',
      );
    }
    final path = _dataUrl(contentType, bytes);
    await _commit(() {
      final users = _rows('users');
      final index = users.indexWhere((u) => u['id'] == userId);
      if (index < 0) throw const AppFailure('Akun tidak ditemukan.');
      users[index] = {...users[index], 'photo_path': path};
      db['users'] = users;
    });
    return path;
  }

  @override
  Future<Uint8List?> downloadPrivateFile(String bucket, String path) async {
    if (path.isEmpty) return null;
    final comma = path.indexOf(',');
    if (!path.startsWith('data:image/') || comma < 0) {
      throw const AppFailure('Berkas gambar tidak tersedia.');
    }
    return base64Decode(path.substring(comma + 1));
  }

  @override
  Future<void> saveEntity(Entity e) => _commit(() {
    final rows = _rows('entities')..removeWhere((x) => x['id'] == e.id);
    rows.add(e.toJson());
    db['entities'] = rows;
  });
  @override
  Future<void> deleteEntity(String id) => _commit(() {
    db['entities'] = _rows('entities')..removeWhere((x) => x['id'] == id);
  });
  @override
  Future<void> saveTenant(Tenant t) => _commit(() {
    db['tenants'] = (_rows('tenants')..removeWhere((x) => x['id'] == t.id))
      ..add(t.toJson());
  });
  @override
  Future<void> saveUser(AppUser u, {String? password}) => _commit(() {
    if (_rows('users').any(
      (x) =>
          x['id'] != u.id &&
          x['email'].toString().toLowerCase() == u.email.toLowerCase(),
    )) {
      throw const AppFailure('Email sudah terdaftar.');
    }
    db['users'] = (_rows('users')..removeWhere((x) => x['id'] == u.id))
      ..add(u.toJson());
    if (password != null && password.isNotEmpty) {
      db['passwords'][u.id] = _hash(password, u.id);
    }
  });
  @override
  Future<void> deleteUser(String id) => _commit(() {
    db['users'] = _rows('users')..removeWhere((x) => x['id'] == id);
    (db['passwords'] as Map).remove(id);
  });
  @override
  Future<void> updateSelf(String name, String phone) => saveUser(
    AppUser.fromJson({...actor.toJson(), 'name': name, 'phone': phone}),
  );
  @override
  Future<void> changePassword(String password) => _commit(() {
    db['passwords'][actor.id] = _hash(password, actor.id);
  });
  @override
  Future<void> resetPassword(String email) async {
    throw const AppFailure(
      'Mode demo tidak mengirim email. Gunakan akun contoh atau minta admin mengatur ulang kata sandi.',
    );
  }

  @override
  Future<QrTicket> issueQr() async {
    if (actor.role != UserRole.student) {
      throw const AppFailure('QR hanya untuk siswa.');
    }
    final value = 'ELRN1:${newId()}';
    final expiry = DateTime.now().add(const Duration(minutes: 5));
    await _commit(() {
      final tickets = Json.from(db['tickets'] as Map);
      tickets.removeWhere(
        (_, v) =>
            DateTime.parse(v['expires'] as String).isBefore(DateTime.now()),
      );
      tickets[value] = {
        'studentId': actor.id,
        'tenantId': actor.tenantId,
        'expires': expiry.toIso8601String(),
      };
      db['tickets'] = tickets;
    });
    return QrTicket(value, expiry);
  }

  @override
  Future<String> resolveQr(String value) async {
    final ticket = (db['tickets'] as Map)[value];
    if (ticket == null ||
        DateTime.parse(ticket['expires'] as String).isBefore(DateTime.now())) {
      throw const AppFailure(
        'QR tidak dikenali atau sudah kedaluwarsa. Minta siswa memperbarui QR.',
      );
    }
    if (actor.tenantId != ticket['tenantId'] ||
        ![
          UserRole.admin,
          UserRole.leader,
          UserRole.teacher,
        ].contains(actor.role)) {
      throw const AppFailure('QR tidak dapat diakses dari akun ini.');
    }
    return ticket['studentId'] as String;
  }
}
