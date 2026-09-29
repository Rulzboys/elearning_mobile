import 'dart:math';

typedef Json = Map<String, dynamic>;

String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

enum UserRole {
  developer('Developer', '/developer'),
  leader('Pimpinan', '/leader'),
  admin('Admin', '/admin'),
  teacher('Guru', '/teacher'),
  student('Siswa', '/student');

  const UserRole(this.label, this.home);
  final String label;
  final String home;
  bool get managesSchool => this == admin || this == leader;
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.tenantId,
    this.classId,
    this.number = '',
    this.phone = '',
    this.photoPath = '',
    this.active = true,
  });

  final String id;
  final String name;
  final String email;
  final String number;
  final String phone;
  final String photoPath;

  final String? tenantId;
  final String? classId;
  final UserRole role;
  final bool active;

  factory AppUser.fromJson(Json j) => AppUser(
    id: j['id'] as String,
    name: j['name'] as String,
    email: j['email'] as String,
    role: UserRole.values.byName(j['role'] as String),
    tenantId: j['tenant_id'] as String?,
    classId: j['class_id'] as String?,
    number: j['number'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    photoPath: j['photo_path'] as String? ?? '',
    active: j['active'] as bool? ?? true,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'tenant_id': tenantId,
    'class_id': classId,
    'number': number,
    'phone': phone,
    'photo_path': photoPath,
    'active': active,
  };
}

class Tenant {
  Tenant({
    required this.id,
    required this.name,
    required this.code,
    required this.expiresAt,
    this.status = 'active',
    this.plan = 'Dasar',
    this.academicYear = '2026/2027',
    this.semester = 'Ganjil',
    this.address = '',
    this.contact = '',
    this.targetCount = 20,
  });
  final String id,
      name,
      code,
      status,
      plan,
      academicYear,
      semester,
      address,
      contact;
  final DateTime expiresAt;
  final int targetCount;
  bool get isActive => status == 'active' && expiresAt.isAfter(DateTime.now());
  String get accessLabel => status == 'active'
      ? (isActive ? 'Aktif' : 'Masa aktif berakhir')
      : 'Ditangguhkan';
  factory Tenant.fromJson(Json j) => Tenant(
    id: j['id'] as String,
    name: j['name'] as String,
    code: j['code'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
    status: j['status'] as String? ?? 'active',
    plan: j['plan'] as String? ?? 'Dasar',
    academicYear: j['academic_year'] as String? ?? '2026/2027',
    semester: j['semester'] as String? ?? 'Ganjil',
    address: j['address'] as String? ?? '',
    contact: j['contact'] as String? ?? '',
    targetCount: (j['target_count'] as num?)?.toInt() ?? 20,
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'status': status,
    'plan': plan,
    'academic_year': academicYear,
    'semester': semester,
    'address': address,
    'contact': contact,
    'target_count': targetCount,
  };
}

class Entity {
  Entity({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.authorId,
  });
  final String id, tenantId, kind;
  final String? authorId;
  final Json data;
  final DateTime createdAt;
  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  int number(String key, [int fallback = 0]) =>
      (data[key] as num?)?.toInt() ?? fallback;
  factory Entity.fromJson(Json j) => Entity(
    id: j['id'] as String,
    tenantId: j['tenant_id'] as String,
    kind: j['kind'] as String,
    data: Json.from(j['data'] as Map),
    createdAt: DateTime.parse(j['created_at'] as String),
    authorId: j['author_id'] as String?,
  );
  Json toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'kind': kind,
    'data': data,
    'created_at': createdAt.toUtc().toIso8601String(),
    'author_id': authorId,
  };
}

class Snapshot {
  const Snapshot(this.users, this.tenants, this.entities);
  final List<AppUser> users;
  final List<Tenant> tenants;
  final List<Entity> entities;
}

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class QrTicket {
  const QrTicket(this.value, this.expiresAt);
  final String value;
  final DateTime expiresAt;
}
