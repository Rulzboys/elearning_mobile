import '../../shared/models/models.dart';

class DemoSeed {
  static const tenantId = '10000000-0000-4000-8000-000000000001';
  static const developerId = '20000000-0000-4000-8000-000000000001';
  static const adminId = '20000000-0000-4000-8000-000000000002';
  static const teacherId = '20000000-0000-4000-8000-000000000003';
  static const studentId = '20000000-0000-4000-8000-000000000004';
  static const otherStudentId = '20000000-0000-4000-8000-000000000005';
  static const classId = '30000000-0000-4000-8000-000000000001';
  static const subjectId = '30000000-0000-4000-8000-000000000002';
  static const assignmentId = '30000000-0000-4000-8000-000000000003';
  static const password = 'Belajar123!';

  static Snapshot create() {
    final now = DateTime.now();
    final users = [
      AppUser(
        id: '20000000-0000-4000-8000-000000000006',
        name: 'Pimpinan Pondok',
        email: 'pimpinan@elearning.test',
        role: UserRole.leader,
        tenantId: tenantId,
      ),
      AppUser(
        id: developerId,
        name: 'Pengelola Platform',
        email: 'developer@elearning.test',
        role: UserRole.developer,
      ),
      AppUser(
        id: adminId,
        name: 'Admin Akademik',
        email: 'admin@elearning.test',
        role: UserRole.admin,
        tenantId: tenantId,
      ),
      AppUser(
        id: teacherId,
        name: 'Ahmad Fauzi',
        email: 'guru@elearning.test',
        role: UserRole.teacher,
        tenantId: tenantId,
        number: 'G-001',
      ),
      AppUser(
        id: studentId,
        name: 'Muhammad Farhan',
        email: 'siswa@elearning.test',
        role: UserRole.student,
        tenantId: tenantId,
        classId: classId,
        number: '20260087',
      ),
      AppUser(
        id: otherStudentId,
        name: 'Aisyah Putri',
        email: 'aisyah@elearning.test',
        role: UserRole.student,
        tenantId: tenantId,
        classId: classId,
        number: '20260088',
      ),
    ];
    Entity item(String id, String kind, Json data, {int daysAgo = 0}) => Entity(
      id: id,
      tenantId: tenantId,
      kind: kind,
      data: data,
      createdAt: now.subtract(Duration(days: daysAgo)),
      authorId: teacherId,
    );
    final entities = <Entity>[
      item(classId, 'classroom', {
        'name': 'VIII A',
        'teacherId': teacherId,
        'academicYear': '2026/2027',
        'targetCount': 20,
      }),
      item(subjectId, 'subject', {
        'name': 'Pendidikan Agama',
        'description': 'Akhlak, ibadah, dan pembelajaran Al-Qur’an.',
      }),
      item(assignmentId, 'assignment', {
        'title': 'Menulis adab menuntut ilmu',
        'description':
            'Tuliskan lima adab menuntut ilmu beserta contoh penerapannya di sekolah atau pesantren.',
        'classId': classId,
        'subjectId': subjectId,
        'teacherId': teacherId,
        'dueAt': now.add(const Duration(days: 3)).toIso8601String(),
      }),
      item(newId(), 'announcement', {
        'title': 'Semangat belajar pekan ini',
        'content':
            'Bawa buku catatan dan perlengkapan belajar. Setoran hafalan dilaksanakan sesuai jadwal pembimbing.',
        'audience': 'all',
        'classId': '',
      }),
      item(newId(), 'material', {
        'title': 'Adab sebelum belajar',
        'content':
            '1. Meluruskan niat untuk mencari ilmu.\n\n2. Mempersiapkan buku dan alat tulis.\n\n3. Menghormati guru serta teman.\n\n4. Mendengarkan penjelasan dengan saksama.\n\n5. Mengulang pelajaran dan bertanya dengan santun.',
        'classId': classId,
        'subjectId': subjectId,
        'teacherId': teacherId,
      }),
      item(newId(), 'schedule', {
        'title': 'Setoran & murajaah',
        'classId': classId,
        'subjectId': subjectId,
        'teacherId': teacherId,
        'weekday': now.weekday,
        'startTime': '07:30',
        'endTime': '08:30',
        'room': 'Ruang belajar A',
      }),
      item(newId(), 'attendance', {
        'studentId': studentId,
        'classId': classId,
        'date':
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'status': 'Hadir',
      }),
    ];
    for (var i = 0; i < 3; i++) {
      final titles = ['Al-Fatihah', 'Al-Ikhlas', 'Al-Falaq'];
      final ends = [7, 4, 5];
      entities.add(
        item(newId(), 'memorization', {
          'studentId': studentId,
          'teacherId': teacherId,
          'classId': classId,
          'title': titles[i],
          'startVerse': 1,
          'endVerse': ends[i],
          'unitKey': '${titles[i].toLowerCase()}|1|${ends[i]}',
          'status': i == 2 ? 'review' : 'completed',
          'fluency': 85 + i,
          'tajwid': 82 + i,
          'makhraj': 84 + i,
          'notes': i == 2
              ? 'Ulangi bacaan pada pertemuan berikutnya.'
              : 'Bacaan baik. Pertahankan murajaah.',
        }, daysAgo: 3 - i),
      );
    }
    return Snapshot(users, [
      Tenant(
        id: tenantId,
        name: 'Pesantren Nusantara',
        code: 'NUSANTARA',
        expiresAt: now.add(const Duration(days: 365)),
        contact: 'Bagian akademik',
        address: 'Indonesia',
      ),
    ], entities);
  }
}
