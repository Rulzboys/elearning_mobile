import '../../shared/models/models.dart';

class AccessPolicy {
  static bool canUse(AppUser? user, Tenant? tenant) =>
      user != null &&
      user.active &&
      (user.role == UserRole.developer || tenant?.isActive == true);

  static bool routeAllowed(UserRole role, String path) {
    if (path.startsWith('/developer')) return role == UserRole.developer;
    if (path.startsWith('/subscription/settings')) {
      return role == UserRole.developer;
    }
    if (path.startsWith('/subscription')) return role != UserRole.developer;
    if (path.startsWith('/leader')) return role == UserRole.leader;
    if (path.startsWith('/spp/settings')) return role.managesSchool;
    if (path.startsWith('/spp')) {
      return role.managesSchool || role == UserRole.student;
    }
    if (path.startsWith('/admin')) return role.managesSchool;
    if (path.startsWith('/teacher/scan') ||
        path.startsWith('/teacher/attendance/scan')) {
      return role == UserRole.teacher;
    }
    if (path.startsWith('/teacher')) {
      return role == UserRole.teacher || role.managesSchool;
    }
    if (path.startsWith('/student')) return role == UserRole.student;
    if (role == UserRole.developer) return path == '/profile';
    return true;
  }

  static bool visible(AppUser u, Entity e, Set<String> classIds) {
    if (e.kind == 'subscription_setting') return true;
    if (e.kind == 'subscription_order') {
      if (u.role == UserRole.developer) return true;
      if (u.tenantId != e.tenantId) return false;
      return u.role.managesSchool || e.text('buyer_id') == u.id;
    }
    if (u.role == UserRole.developer || u.tenantId != e.tenantId) return false;
    if (e.kind == 'qris_setting') return u.role.managesSchool;
    if (e.kind == 'spp_invoice' || e.kind == 'spp_payment') {
      return u.role.managesSchool ||
          (u.role == UserRole.student && e.text('student_id') == u.id);
    }
    if (u.role.managesSchool) return true;
    if (e.kind == 'subject') return true;
    if (e.kind == 'classroom') return classIds.contains(e.id);
    if (e.kind == 'announcement') {
      final audience = e.text('audience', 'all');
      return (audience == 'all' || audience == u.role.name) &&
          (e.text('classId').isEmpty || classIds.contains(e.text('classId')));
    }
    if (!classIds.contains(e.text('classId'))) return false;
    if (u.role == UserRole.student &&
        ['memorization', 'submission', 'attendance'].contains(e.kind)) {
      return e.text('studentId') == u.id;
    }
    return true;
  }

  static int completedUnits(Iterable<Entity> records) {
    final sorted = records.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latest = <String, Entity>{};
    for (final e in sorted) {
      latest.putIfAbsent(e.text('unitKey', e.id), () => e);
    }
    return latest.values.where((e) => e.text('status') == 'completed').length;
  }
}
