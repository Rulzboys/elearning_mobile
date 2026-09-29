import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/data/demo_repository.dart';
import '../../core/data/repository.dart';
import '../../core/data/supabase_repository.dart';
import '../../core/services/access_policy.dart';
import '../../core/services/student_card_code.dart';
import '../models/models.dart';

final appProvider = ChangeNotifierProvider<AppStore>(
  (ref) => throw StateError('AppStore belum dipasang.'),
);

class AppStore extends ChangeNotifier {
  AppStore(this.repository);
  final LearningRepository repository;
  Snapshot _snapshot = const Snapshot([], [], []);
  String? _uid;
  bool busy = false, recovery = false, refreshing = false;
  String? syncError;
  Set<String> readIds = {};
  Timer? _timer;
  StreamSubscription<AuthState>? _authSub;
  AppUser? get user => _snapshot.users.where((u) => u.id == _uid).firstOrNull;
  bool get hasSession => _uid != null;
  Tenant? get tenant =>
      _snapshot.tenants.where((t) => t.id == user?.tenantId).firstOrNull;
  bool get canUse => AccessPolicy.canUse(user, tenant);
  bool get isDemo => repository is DemoRepository;
  UserRole? get role => user?.role;
  bool get isManager => role?.managesSchool == true;
  bool get isStaff => role == UserRole.teacher || isManager;
  bool get canScanStudentQr => role == UserRole.teacher;
  String get blockedReason => user == null
      ? 'Akun belum memiliki profil. Hubungi pengelola platform.'
      : !user!.active
      ? 'Akun Anda dinonaktifkan. Hubungi admin instansi.'
      : tenant == null
      ? 'Instansi tidak ditemukan. Hubungi pengelola platform.'
      : '${tenant!.accessLabel}. Hubungi admin instansi untuk melanjutkan kegiatan belajar.';
  String get home => user?.role.home ?? '/login';

  Future<void> initialize() async {
    await repository.initialize();
    _uid = await repository.restoreUserId();
    if (_uid != null) await refresh();
    if (!isDemo) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
        state,
      ) {
        // Never await Supabase calls inside its synchronous auth callback.
        Future<void>(() async {
          if (state.event == AuthChangeEvent.signedOut) {
            _uid = null;
            _snapshot = const Snapshot([], [], []);
            readIds = {};
            recovery = false;
            notifyListeners();
          } else if (state.session != null) {
            _uid = state.session!.user.id;
            if (state.event == AuthChangeEvent.passwordRecovery) {
              recovery = true;
            }
            try {
              await refresh();
            } catch (_) {
              /* surfaced by syncError */
            }
          }
        });
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (hasSession && !busy) unawaited(refresh().catchError((Object _) {}));
      notifyListeners(); // Expiration must also apply without a new response.
    });
  }

  Set<String> get classIds {
    final u = user;
    if (u == null) return {};
    if (u.role == UserRole.student) return {if (u.classId != null) u.classId!};
    return _snapshot.entities
        .where(
          (e) =>
              e.kind == 'classroom' &&
              e.tenantId == u.tenantId &&
              (u.role.managesSchool || e.text('teacherId') == u.id),
        )
        .map((e) => e.id)
        .toSet();
  }

  List<Entity> items(String kind) {
    if (!canUse) return [];
    return _snapshot.entities
        .where(
          (e) => e.kind == kind && AccessPolicy.visible(user!, e, classIds),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Entity? entity(String id) => _snapshot.entities
      .where(
        (e) => e.id == id && canUse && AccessPolicy.visible(user!, e, classIds),
      )
      .firstOrNull;
  List<Tenant> get tenants => canUse && role == UserRole.developer
      ? List.unmodifiable(_snapshot.tenants)
      : [if (tenant != null) tenant!];
  List<AppUser> get users {
    if (!canUse) return [];
    final u = user!;
    return _snapshot.users.where((x) {
      if (x.id == u.id) return true;
      if (role == UserRole.developer) return x.role.managesSchool;
      if (x.tenantId != u.tenantId) return false;
      if (isManager) return x.role != UserRole.developer;
      if (role == UserRole.teacher) {
        return x.role == UserRole.student && classIds.contains(x.classId);
      }
      return x.role == UserRole.teacher &&
          items('classroom').any((c) => c.text('teacherId') == x.id);
    }).toList();
  }

  List<AppUser> members(UserRole r) =>
      users.where((u) => u.role == r).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  AppUser? member(String id) => users.where((u) => u.id == id).firstOrNull;
  String className(String? id) =>
      id == null ? 'Belum ada kelas' : entity(id)?.text('name') ?? 'Kelas';
  List<Entity> recordsFor(String studentId) => items(
    'memorization',
  ).where((e) => e.text('studentId') == studentId).toList();
  int completed(String studentId) =>
      AccessPolicy.completedUnits(recordsFor(studentId));
  int target(String studentId) =>
      entity(
        member(studentId)?.classId ?? '',
      )?.number('targetCount', tenant?.targetCount ?? 20) ??
      tenant?.targetCount ??
      20;
  double progress(String studentId) =>
      (completed(studentId) / target(studentId)).clamp(0, 1).toDouble();

  Future<void>? _refreshTask;
  Future<void> refresh() {
    if (_uid == null) return Future<void>.value();
    return _refreshTask ??= _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    refreshing = true;
    final requestedUid = _uid;
    try {
      final data = await repository.load();
      if (_uid != requestedUid) return;
      _snapshot = data;
      syncError = null;
      final prefs = await SharedPreferences.getInstance();
      readIds = (prefs.getStringList('read_$_uid') ?? []).toSet();
    } catch (_) {
      syncError = 'Data belum diperbarui. Periksa koneksi lalu coba lagi.';
      rethrow;
    } finally {
      refreshing = false;
      _refreshTask = null;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _uid = await repository.login(email, password);
    try {
      await refresh();
    } catch (_) {
      await repository.logout();
      _uid = null;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await repository.logout();
    _uid = null;
    recovery = false;
    _snapshot = const Snapshot([], [], []);
    readIds = {};
    syncError = null;
    notifyListeners();
  }

  Future<void> transaction(Future<void> Function() action) async {
    if (busy) throw const AppFailure('Tunggu penyimpanan sebelumnya selesai.');
    busy = true;
    notifyListeners();
    try {
      await action();
      if (hasSession) {
        try {
          await refresh();
        } catch (_) {
          syncError =
              'Perubahan tersimpan, tetapi tampilan belum diperbarui. Tarik layar untuk mencoba lagi.';
        }
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void requireAccess() {
    if (!canUse) throw AppFailure(blockedReason);
  }

  bool canEdit(Entity e) =>
      canUse &&
      (isManager ||
          (role == UserRole.teacher &&
              [
                'memorization',
                'assignment',
                'schedule',
                'announcement',
                'material',
                'attendance',
                'submission',
              ].contains(e.kind) &&
              classIds.contains(e.text('classId')) &&
              (e.kind != 'announcement' || e.authorId == user!.id)));

  Future<void> save(String kind, Json input, {Entity? previous}) async {
    requireAccess();
    final d = Json.from(input);
    final u = user!;
    if (u.role == UserRole.developer) {
      throw const AppFailure('Gunakan menu pengelolaan instansi.');
    }
    if (previous != null &&
        (previous.tenantId != u.tenantId || previous.kind != kind)) {
      throw const AppFailure('Data tidak sesuai instansi.');
    }
    if (![
      'classroom',
      'subject',
      'memorization',
      'assignment',
      'submission',
      'schedule',
      'announcement',
      'material',
      'attendance',
    ].contains(kind)) {
      throw const AppFailure('Jenis data tidak dikenal.');
    }
    if (u.role == UserRole.student) {
      if (kind != 'submission' ||
          (previous != null && previous.text('studentId') != u.id)) {
        throw const AppFailure('Akses ditolak.');
      }
      final a = entity(d['assignmentId']?.toString() ?? '');
      if (a?.kind != 'assignment' || a!.text('classId') != u.classId) {
        throw const AppFailure('Tugas tidak ditemukan.');
      }
      if (DateTime.parse(a.text('dueAt')).isBefore(DateTime.now())) {
        throw const AppFailure('Batas pengumpulan sudah berakhir.');
      }
      if (previous?.data['score'] != null) {
        throw const AppFailure(
          'Jawaban yang sudah dinilai tidak dapat diubah.',
        );
      }
      if (previous != null && previous.text('assignmentId') != a.id) {
        throw const AppFailure('Tugas pada jawaban tidak dapat diganti.');
      }
      d.clear();
      d.addAll({
        'assignmentId': a.id,
        'studentId': u.id,
        'classId': u.classId,
        'answer': input['answer']?.toString().trim(),
        'submittedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } else if (u.role == UserRole.teacher) {
      if (['classroom', 'subject'].contains(kind) ||
          !classIds.contains(d['classId'])) {
        throw const AppFailure('Pilih kelas yang Anda bimbing.');
      }
      if (previous != null && !canEdit(previous)) {
        throw const AppFailure('Data tidak dapat diubah.');
      }
      if (kind == 'announcement' &&
          !['all', 'student'].contains(d['audience'])) {
        throw const AppFailure(
          'Pengumuman guru ditujukan kepada siswa kelas bimbingan.',
        );
      }
    }
    String requiredText(String key) {
      final value = d[key]?.toString().trim() ?? '';
      if (value.isEmpty) throw const AppFailure('Lengkapi semua kolom wajib.');
      d[key] = value;
      return value;
    }

    if (['classroom', 'subject'].contains(kind)) requiredText('name');
    if ([
      'memorization',
      'assignment',
      'schedule',
      'announcement',
      'material',
    ].contains(kind)) {
      requiredText('title');
    }
    if (['announcement', 'material'].contains(kind)) requiredText('content');
    if (kind == 'assignment') {
      requiredText('description');
      if (DateTime.tryParse(requiredText('dueAt')) == null) {
        throw const AppFailure('Tanggal tugas tidak valid.');
      }
      if (previous != null &&
          previous.text('classId') != d['classId'] &&
          items(
            'submission',
          ).any((e) => e.text('assignmentId') == previous.id)) {
        throw const AppFailure(
          'Tugas sudah memiliki jawaban. Kelas tidak dapat diganti.',
        );
      }
    }
    if (!['subject', 'classroom', 'announcement'].contains(kind) ||
        (d['classId']?.toString().isNotEmpty ?? false)) {
      final c = entity(d['classId']?.toString() ?? '');
      if (c?.kind != 'classroom') {
        throw const AppFailure('Kelas tidak ditemukan.');
      }
    }
    if (kind == 'classroom') {
      final t = member(requiredText('teacherId'));
      if (t?.role != UserRole.teacher || !t!.active) {
        throw const AppFailure('Pilih guru aktif.');
      }
      final n = d['targetCount'];
      if (n is! int || n < 1 || n > 1000) {
        throw const AppFailure('Target harus 1–1000 bagian.');
      }
    }
    if (['assignment', 'material', 'schedule'].contains(kind)) {
      if (entity(d['subjectId']?.toString() ?? '')?.kind != 'subject') {
        throw const AppFailure('Pilih mata pelajaran.');
      }
      d['teacherId'] = role == UserRole.teacher
          ? u.id
          : entity(d['classId'] as String)!.text('teacherId');
    }
    if (['memorization', 'attendance', 'submission'].contains(kind)) {
      if (previous != null &&
          (previous.text('studentId') != d['studentId'] ||
              previous.text('classId') != d['classId'])) {
        throw const AppFailure(
          'Siswa dan kelas pada riwayat tidak dapat diganti.',
        );
      }
      final s = member(d['studentId']?.toString() ?? '');
      if (s?.role != UserRole.student || s!.classId != d['classId']) {
        throw const AppFailure('Siswa tidak terdaftar di kelas ini.');
      }
    }
    if (kind == 'memorization') {
      for (final k in ['fluency', 'tajwid', 'makhraj']) {
        if (d[k] is! int || (d[k] as int) < 0 || (d[k] as int) > 100) {
          throw const AppFailure('Nilai harus 0–100.');
        }
      }
      if (d['startVerse'] is! int ||
          d['endVerse'] is! int ||
          (d['startVerse'] as int) < 1 ||
          (d['endVerse'] as int) < (d['startVerse'] as int)) {
        throw const AppFailure('Rentang ayat tidak valid.');
      }
      if (!['inProgress', 'review', 'completed'].contains(d['status'])) {
        throw const AppFailure('Status hafalan tidak valid.');
      }
      d['unitKey'] =
          '${(d['title'] as String).toLowerCase()}|${d['startVerse']}|${d['endVerse']}';
      d['teacherId'] = u.id;
    }
    if (kind == 'submission') {
      requiredText('answer');
      final duplicate = items(kind).where(
        (e) =>
            e.text('assignmentId') == d['assignmentId'] &&
            e.text('studentId') == d['studentId'] &&
            e.id != previous?.id,
      );
      if (duplicate.isNotEmpty) {
        throw const AppFailure(
          'Jawaban sudah ada. Buka jawaban sebelumnya untuk mengubah.',
        );
      }
      if (isStaff) {
        if (previous == null) {
          throw const AppFailure('Jawaban harus dikumpulkan oleh siswa.');
        }
        if (d['score'] is! int ||
            (d['score'] as int) < 0 ||
            (d['score'] as int) > 100) {
          throw const AppFailure('Nilai harus 0–100.');
        }
        final score = d['score'];
        final feedback = d['feedback'];
        d.clear();
        d.addAll({
          ...previous.data,
          'score': score,
          'feedback': feedback,
          'gradedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }
    if (kind == 'announcement' &&
        !['all', 'student', 'teacher', 'admin'].contains(d['audience'])) {
      throw const AppFailure('Penerima tidak valid.');
    }
    if (kind == 'attendance') {
      if (!['Hadir', 'Izin', 'Sakit', 'Alpa'].contains(d['status']) ||
          DateTime.tryParse(requiredText('date')) == null) {
        throw const AppFailure('Presensi tidak valid.');
      }
      if (items(kind).any(
        (e) =>
            e.id != previous?.id &&
            e.text('studentId') == d['studentId'] &&
            e.text('date') == d['date'],
      )) {
        throw const AppFailure('Presensi tanggal ini sudah ada.');
      }
    }
    if (kind == 'schedule') {
      final pattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
      if (d['weekday'] is! int ||
          (d['weekday'] as int) < 1 ||
          (d['weekday'] as int) > 7 ||
          !pattern.hasMatch(requiredText('startTime')) ||
          !pattern.hasMatch(requiredText('endTime')) ||
          (d['endTime'] as String).compareTo(d['startTime'] as String) <= 0) {
        throw const AppFailure('Hari atau jam jadwal tidak valid.');
      }
      if (items(kind).any(
        (e) =>
            e.id != previous?.id &&
            e.number('weekday') == d['weekday'] &&
            (e.text('classId') == d['classId'] ||
                e.text('teacherId') == d['teacherId']) &&
            e.text('startTime').compareTo(d['endTime'] as String) < 0 &&
            e.text('endTime').compareTo(d['startTime'] as String) > 0,
      )) {
        throw const AppFailure(
          'Jadwal berbenturan dengan kelas atau guru yang sama.',
        );
      }
    }
    await repository.saveEntity(
      Entity(
        id: previous?.id ?? newId(),
        tenantId: u.tenantId!,
        kind: kind,
        data: d,
        createdAt: previous?.createdAt ?? DateTime.now(),
        authorId: previous?.authorId ?? u.id,
      ),
    );
  }

  Future<void> remove(Entity e) async {
    requireAccess();
    if (!canEdit(e)) {
      throw const AppFailure('Data tidak dapat dihapus dari akun ini.');
    }
    if (['classroom', 'subject', 'assignment'].contains(e.kind)) {
      final key = {
        'classroom': 'classId',
        'subject': 'subjectId',
        'assignment': 'assignmentId',
      }[e.kind]!;
      if (_snapshot.entities.any((x) => x.text(key) == e.id) ||
          (e.kind == 'classroom' && users.any((x) => x.classId == e.id))) {
        throw const AppFailure(
          'Data masih digunakan. Pindahkan atau hapus data terkait terlebih dahulu.',
        );
      }
    }
    await repository.deleteEntity(e.id);
  }

  Future<void> saveUser(AppUser value, {String? password}) async {
    requireAccess();
    if (role == UserRole.developer) {
      if (!value.role.managesSchool ||
          !tenants.any((t) => t.id == value.tenantId)) {
        throw const AppFailure(
          'Developer mengelola Admin dan Pimpinan instansi.',
        );
      }
    } else if (!isManager ||
        value.tenantId != user!.tenantId ||
        ![
          UserRole.student,
          UserRole.teacher,
          if (role == UserRole.leader) UserRole.admin,
        ].contains(value.role)) {
      throw const AppFailure('Akses pengelolaan akun ditolak.');
    }
    if (value.id == user!.id) {
      throw const AppFailure('Gunakan menu profil untuk akun sendiri.');
    }
    if (value.name.trim().isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.email)) {
      throw const AppFailure('Nama dan email wajib valid.');
    }
    final old = member(value.id);
    if (old == null && (password == null || password.length < 8)) {
      throw const AppFailure('Kata sandi akun baru minimal 8 karakter.');
    }
    if (password != null && password.isNotEmpty && password.length < 8) {
      throw const AppFailure('Kata sandi minimal 8 karakter.');
    }
    if (value.role == UserRole.student &&
        value.classId != null &&
        entity(value.classId!)?.kind != 'classroom') {
      throw const AppFailure('Kelas siswa tidak valid.');
    }
    if (old != null &&
        old.classId != value.classId &&
        _snapshot.entities.any((e) => e.text('studentId') == value.id)) {
      throw const AppFailure(
        'Siswa sudah memiliki riwayat belajar. Pertahankan kelas agar riwayat tetap terhubung.',
      );
    }
    if (!value.active &&
        _snapshot.entities.any(
          (e) => e.kind == 'classroom' && e.text('teacherId') == value.id,
        )) {
      throw const AppFailure(
        'Ganti guru pembimbing kelas sebelum menonaktifkan akun.',
      );
    }
    await repository.saveUser(value, password: password);
  }

  Future<void> removeUser(AppUser value) async {
    requireAccess();
    if (value.id == user!.id ||
        (isManager &&
            (value.tenantId != user!.tenantId ||
                ![
                  UserRole.teacher,
                  UserRole.student,
                  if (role == UserRole.leader) UserRole.admin,
                ].contains(value.role))) ||
        (role == UserRole.developer && !value.role.managesSchool) ||
        ![UserRole.developer, UserRole.admin, UserRole.leader].contains(role)) {
      throw const AppFailure('Akun tidak dapat dihapus.');
    }
    if (_snapshot.entities.any(
      (e) =>
          e.authorId == value.id ||
          e.text('student_id') == value.id ||
          e.text('reviewed_by') == value.id ||
          e.text('studentId') == value.id ||
          e.text('teacherId') == value.id,
    )) {
      throw const AppFailure(
        'Akun memiliki riwayat. Gunakan Nonaktifkan untuk mempertahankannya.',
      );
    }
    await repository.deleteUser(value.id);
  }

  Future<void> saveTenant(Tenant value) async {
    requireAccess();
    if (isManager) {
      if (value.id != tenant!.id ||
          value.status != tenant!.status ||
          value.plan != tenant!.plan ||
          value.expiresAt != tenant!.expiresAt ||
          value.code != tenant!.code) {
        throw const AppFailure(
          'Pengaturan kontrak hanya dapat diubah Developer.',
        );
      }
    } else if (role != UserRole.developer) {
      throw const AppFailure('Akses ditolak.');
    }
    if (value.name.trim().isEmpty ||
        !RegExp(r'^[A-Z0-9_-]{3,24}$').hasMatch(value.code) ||
        value.targetCount < 1 ||
        value.targetCount > 1000) {
      throw const AppFailure('Nama, kode instansi, atau target belum valid.');
    }
    if (tenants.any((t) => t.id != value.id && t.code == value.code)) {
      throw const AppFailure('Kode instansi sudah digunakan.');
    }
    await repository.saveTenant(value);
  }

  Future<QrTicket> issueQr() async {
    requireAccess();
    return repository.issueQr();
  }

  Future<AppUser> resolveQr(String value) async {
    requireAccess();
    if (!canScanStudentQr) {
      throw const AppFailure(
        'QR bukan milik E-Learning atau tidak dapat diakses.',
      );
    }
    final card = StudentCardCode.decode(value);
    final String id;
    if (card != null) {
      // Refresh through authenticated RLS before resolving any printed reference.
      id = card.studentId;
    } else if (RegExp(r'^ELRN1:[0-9a-f-]{36}$').hasMatch(value.trim())) {
      id = await repository.resolveQr(value.trim());
    } else {
      throw const AppFailure(
        'QR tidak dikenali. Gunakan kartu siswa E-Learning.',
      );
    }
    await refresh();
    requireAccess();
    final s = member(id);
    if (!canScanStudentQr ||
        s == null ||
        !s.active ||
        s.role != UserRole.student ||
        s.tenantId != user?.tenantId ||
        (card != null && card.tenantId != s.tenantId) ||
        !classIds.contains(s.classId)) {
      throw const AppFailure(
        'Siswa tidak berada di kelas yang dapat Anda akses.',
      );
    }
    return s;
  }

  Future<void> markRead(Iterable<String> ids) async {
    final next = {...readIds, ...ids};
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList('read_$_uid', next.toList())) {
      throw const AppFailure('Status baca belum tersimpan.');
    }
    readIds = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_authSub?.cancel());
    super.dispose();
  }
}

AppStore makeStore() =>
    AppStore(AppConfig.isDemo ? DemoRepository() : SupabaseRepository());
