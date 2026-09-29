-- Additive upgrade for E-Learning baseline 202609080001. Run BEFORE the billing migration.
begin;
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('developer','leader','admin','teacher','student'));
create or replace function public.class_access(p_class uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare a public.profiles; c public.learning_entities;
begin
  a := public.actor_profile();
  if a.id is null or not a.active or not public.tenant_active(a.tenant_id) then return false; end if;
  select * into c from public.learning_entities where id=p_class and kind='classroom' and tenant_id=a.tenant_id;
  if c.id is null then return false; end if;
  return a.role in ('admin','leader') or (a.role='teacher' and c.data->>'teacherId'=a.id::text) or (a.role='student' and a.class_id=p_class);
end;
$$;

create or replace function public.entity_visible(p_id uuid,p_tenant uuid,p_kind text,p_data jsonb) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare a public.profiles; class_id uuid;
begin
  a:=public.actor_profile();
  if a.id is null or not a.active or a.role='developer' or a.tenant_id<>p_tenant or not public.tenant_active(p_tenant) then return false; end if;
  if a.role in ('admin','leader') then return true; end if;
  if p_kind='subject' then return true; end if;
  if p_kind='classroom' then return public.class_access(p_id); end if;
  class_id:=nullif(p_data->>'classId','')::uuid;
  if p_kind='announcement' then
    return p_data->>'audience' in ('all',a.role) and (class_id is null or public.class_access(class_id));
  end if;
  if class_id is null or not public.class_access(class_id) then return false; end if;
  if a.role='student' and p_kind in ('memorization','attendance','submission') then return p_data->>'studentId'=a.id::text; end if;
  return true;
end;
$$;

create or replace function public.profile_visible(p_id uuid,p_tenant uuid,p_role text,p_class uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare a public.profiles;
begin
  a:=public.actor_profile();
  if a.id=p_id then return true; end if; -- lets a suspended account read its own access status
  if a.id is null or not a.active then return false; end if;
  if a.role='developer' then return p_role in ('admin','leader'); end if;
  if a.tenant_id<>p_tenant or p_tenant is null or not public.tenant_active(a.tenant_id) then return false; end if;
  if a.role in ('admin','leader') then return p_role<>'developer'; end if;
  if a.role='teacher' then return p_role='student' and public.class_access(p_class); end if;
  return p_role='teacher' and exists(select 1 from public.learning_entities c where c.id=a.class_id and c.data->>'teacherId'=p_id::text);
end;
$$;

create or replace function public.save_tenant(p_tenant jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.profiles; old public.tenants; t public.tenants;
begin
  a:=public.assert_active_actor();
  t:=jsonb_populate_record(null::public.tenants,p_tenant);
  perform pg_advisory_xact_lock(hashtextextended(t.id::text,0));
  select * into old from public.tenants where id=t.id for update;
  if a.role in ('admin','leader') then
    if old.id is null or old.id<>a.tenant_id or t.id<>a.tenant_id or
      t.code is distinct from old.code or t.plan is distinct from old.plan or
      t.status is distinct from old.status or t.expires_at is distinct from old.expires_at then
      raise exception 'Pengaturan kontrak hanya dapat diubah Developer.';
    end if;
  elsif a.role<>'developer' then raise exception 'Akses ditolak.'; end if;
  insert into public.tenants select t.* on conflict(id) do update set
    name=excluded.name,code=excluded.code,status=excluded.status,plan=excluded.plan,expires_at=excluded.expires_at,
    academic_year=excluded.academic_year,semester=excluded.semester,address=excluded.address,contact=excluded.contact,target_count=excluded.target_count;
end;
$$;

create or replace function public.save_learning_entity(p_entity jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.profiles; old public.learning_entities; c public.learning_entities;
  assignment public.learning_entities; student public.profiles; teacher public.profiles;
  d jsonb; ident uuid; tenant uuid; kind_name text; class_id uuid; k text; n integer;
begin
  a:=public.assert_active_actor();
  if a.role='developer' then raise exception 'Menu akademik hanya untuk akun instansi.'; end if;
  tenant:=(p_entity->>'tenant_id')::uuid;
  if tenant is distinct from a.tenant_id then raise exception 'Instansi tidak sesuai.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(tenant::text,0));
  ident:=(p_entity->>'id')::uuid; kind_name:=p_entity->>'kind'; d:=p_entity->'data';
  if ident is null or jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>100000 then raise exception 'Format data tidak valid atau terlalu panjang.'; end if;
  if kind_name is null or kind_name not in ('classroom','subject','announcement','material','schedule','assignment','submission','memorization','attendance') then raise exception 'Jenis data tidak valid.'; end if;
  select * into old from public.learning_entities where id=ident for update;
  if old.id is not null and (old.tenant_id<>tenant or old.kind<>kind_name) then raise exception 'Data tidak sesuai.'; end if;
  if old.id is not null and not public.entity_visible(old.id,old.tenant_id,old.kind,old.data) then raise exception 'Akses ditolak.'; end if;

  if a.role='student' then
    if kind_name<>'submission' or (old.id is not null and old.data->>'studentId'<>a.id::text) then raise exception 'Akses ditolak.'; end if;
    select * into assignment from public.learning_entities where id=(d->>'assignmentId')::uuid and kind='assignment' and tenant_id=tenant;
    if assignment.id is null or assignment.data->>'classId' is distinct from a.class_id::text then raise exception 'Tugas tidak dapat diakses.'; end if;
    if (assignment.data->>'dueAt')::timestamptz<now() then raise exception 'Batas pengumpulan sudah berakhir.'; end if;
    if old.id is not null and (old.data ? 'score' or old.data->>'assignmentId'<>assignment.id::text) then raise exception 'Jawaban yang dinilai tidak dapat diubah.'; end if;
    d:=jsonb_build_object('assignmentId',assignment.id,'studentId',a.id,'classId',a.class_id,'answer',btrim(d->>'answer'),'submittedAt',now());
  elsif a.role='teacher' then
    if kind_name in ('classroom','subject') or not public.class_access(nullif(d->>'classId','')::uuid) then raise exception 'Pilih kelas bimbingan Anda.'; end if;
    if kind_name='announcement' and ((old.id is not null and old.author_id<>a.id) or d->>'audience' not in ('all','student')) then raise exception 'Pengumuman tidak dapat diubah oleh akun ini.'; end if;
  elsif a.role not in ('admin','leader') then raise exception 'Akses ditolak.'; end if;

  if kind_name in ('classroom','subject') then
    if coalesce(length(btrim(d->>'name')),0) not between 1 and 160 then raise exception 'Nama wajib diisi, maksimal 160 karakter.'; end if;
  end if;
  if kind_name in ('assignment','memorization','announcement','material','schedule') then
    if coalesce(length(btrim(d->>'title')),0) not between 1 and 200 then raise exception 'Judul wajib diisi, maksimal 200 karakter.'; end if;
  end if;
  if kind_name in ('announcement','material') and coalesce(length(btrim(d->>'content')),0)=0 then raise exception 'Isi wajib dilengkapi.'; end if;

  class_id:=nullif(d->>'classId','')::uuid;
  if kind_name not in ('classroom','subject','announcement') or class_id is not null then
    select * into c from public.learning_entities where id=class_id and tenant_id=tenant and kind='classroom';
    if c.id is null then raise exception 'Kelas tidak valid.'; end if;
  end if;
  if old.id is not null and kind_name in ('submission','memorization','attendance') and
    (d->>'studentId' is distinct from old.data->>'studentId' or d->>'classId' is distinct from old.data->>'classId') then raise exception 'Siswa dan kelas pada riwayat tidak dapat diganti.'; end if;

  if kind_name='classroom' then
    select * into teacher from public.profiles where id=(d->>'teacherId')::uuid and tenant_id=tenant and role='teacher' and active;
    if teacher.id is null then raise exception 'Pilih guru aktif dari instansi yang sama.'; end if;
    if coalesce(d->>'targetCount','') !~ '^[0-9]+$' or (d->>'targetCount')::int not between 1 and 1000 then raise exception 'Target harus 1–1000 bagian.'; end if;
    if coalesce(length(btrim(d->>'academicYear')),0)=0 then raise exception 'Tahun ajaran wajib diisi.'; end if;
  end if;
  if kind_name in ('assignment','schedule','material') then
    if not exists(select 1 from public.learning_entities e where e.id=(d->>'subjectId')::uuid and e.tenant_id=tenant and e.kind='subject') then raise exception 'Mata pelajaran tidak valid.'; end if;
    d:=d||jsonb_build_object('teacherId',case when a.role='teacher' then a.id::text else c.data->>'teacherId' end);
  end if;
  if kind_name in ('memorization','attendance','submission') then
    select * into student from public.profiles where id=(d->>'studentId')::uuid and tenant_id=tenant and role='student';
    if student.id is null or student.class_id is distinct from class_id then raise exception 'Siswa tidak sesuai kelas.'; end if;
  end if;
  if kind_name='announcement' and (d->>'audience' is null or d->>'audience' not in ('all','student','teacher','admin')) then raise exception 'Penerima tidak valid.'; end if;
  if kind_name='assignment' then
    if coalesce(length(btrim(d->>'description')),0)=0 or d->>'dueAt' is null then raise exception 'Instruksi dan batas waktu wajib diisi.'; end if;
    perform (d->>'dueAt')::timestamptz;
    if old.id is not null and d->>'classId' is distinct from old.data->>'classId' and exists(
      select 1 from public.learning_entities e where e.kind='submission' and e.data->>'assignmentId'=ident::text) then raise exception 'Tugas sudah memiliki jawaban. Kelas tidak dapat diganti.'; end if;
  end if;
  if kind_name='memorization' then
    foreach k in array array['fluency','tajwid','makhraj'] loop
      if coalesce(d->>k,'') !~ '^[0-9]+$' then raise exception 'Nilai harus angka bulat 0–100.'; end if;
      n:=(d->>k)::integer;
      if n not between 0 and 100 then raise exception 'Nilai harus 0–100.'; end if;
    end loop;
    if coalesce(d->>'startVerse','') !~ '^[0-9]+$' or coalesce(d->>'endVerse','') !~ '^[0-9]+$' or
      (d->>'startVerse')::int<1 or (d->>'endVerse')::int<(d->>'startVerse')::int then raise exception 'Rentang ayat tidak valid.'; end if;
    if d->>'status' is null or d->>'status' not in ('inProgress','review','completed') then raise exception 'Status setoran tidak valid.'; end if;
    d:=d||jsonb_build_object('teacherId',a.id,'unitKey',lower(btrim(d->>'title'))||'|'||(d->>'startVerse')||'|'||(d->>'endVerse'));
  end if;
  if kind_name='submission' then
    if coalesce(length(btrim(d->>'answer')),0)=0 then raise exception 'Jawaban wajib diisi.'; end if;
    if a.role in ('teacher','admin','leader') then
      if old.id is null then raise exception 'Jawaban harus dikumpulkan oleh siswa.'; end if;
      if coalesce(d->>'score','') !~ '^[0-9]+$' or (d->>'score')::int not between 0 and 100 then raise exception 'Nilai harus 0–100.'; end if;
      d:=old.data||jsonb_build_object('score',(d->>'score')::int,'feedback',coalesce(d->>'feedback',''),'gradedAt',now());
    end if;
  end if;
  if kind_name='attendance' then
    if d->>'status' is null or d->>'status' not in ('Hadir','Izin','Sakit','Alpa') or coalesce(d->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Presensi tidak valid.'; end if;
    perform (d->>'date')::date; -- attendance is a local calendar date, not the server's UTC date
  end if;
  if kind_name='schedule' then
    if coalesce(d->>'weekday','') !~ '^[1-7]$' or coalesce(d->>'startTime','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or
      coalesce(d->>'endTime','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or (d->>'startTime') >= (d->>'endTime') then raise exception 'Hari dan jam tidak valid.'; end if;
    if exists(select 1 from public.learning_entities e where e.id<>ident and e.tenant_id=tenant and e.kind='schedule' and
      e.data->>'weekday'=d->>'weekday' and (e.data->>'classId'=d->>'classId' or e.data->>'teacherId'=d->>'teacherId') and
      e.data->>'startTime'<d->>'endTime' and e.data->>'endTime'>d->>'startTime') then raise exception 'Jadwal berbenturan dengan kelas atau guru yang sama.'; end if;
  end if;
  insert into public.learning_entities(id,tenant_id,kind,data,author_id,created_at)
    values(ident,tenant,kind_name,d,coalesce(old.author_id,a.id),coalesce(old.created_at,now()))
    on conflict(id) do update set data=excluded.data;
exception when unique_violation then raise exception 'Data dengan siswa dan tugas/tanggal yang sama sudah ada.';
end;
$$;

create or replace function public.delete_learning_entity(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.profiles; e public.learning_entities; ref_key text;
begin
  a:=public.assert_active_actor();
  perform pg_advisory_xact_lock(hashtextextended(a.tenant_id::text,0));
  select * into e from public.learning_entities where id=p_id for update;
  if e.id is null or e.tenant_id is distinct from a.tenant_id then raise exception 'Data tidak ditemukan.'; end if;
  if a.role='teacher' then
    if e.kind in ('classroom','subject') or not public.class_access(nullif(e.data->>'classId','')::uuid) or
      (e.kind='announcement' and e.author_id<>a.id) then raise exception 'Akses ditolak.'; end if;
  elsif a.role not in ('admin','leader') then raise exception 'Akses ditolak.'; end if;
  ref_key:=case e.kind when 'classroom' then 'classId' when 'subject' then 'subjectId' when 'assignment' then 'assignmentId' end;
  if ref_key is not null and exists(select 1 from public.learning_entities r where r.data->>ref_key=p_id::text) then raise exception 'Data masih dipakai. Hapus atau pindahkan data terkait terlebih dahulu.'; end if;
  if exists(select 1 from public.profiles p where p.class_id=p_id) then raise exception 'Kelas masih memiliki siswa.'; end if;
  delete from public.learning_entities where id=p_id;
end;
$$;

create or replace function public.resolve_student_qr(p_value text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a public.profiles; ticket public.student_qr_tickets; student public.profiles;
begin
  a:=public.assert_active_actor();
  if a.role not in ('teacher','admin','leader') or p_value !~ '^ELRN1:[0-9a-f-]{36}$' then raise exception 'QR tidak dapat diakses.'; end if;
  select * into ticket from public.student_qr_tickets where token=substring(p_value from 7)::uuid and expires_at>now() and tenant_id=a.tenant_id;
  if ticket.token is null then raise exception 'QR tidak dikenali atau kedaluwarsa.'; end if;
  select * into student from public.profiles where id=ticket.student_id and active;
  if student.id is null or not public.class_access(student.class_id) then raise exception 'Siswa bukan anggota kelas bimbingan Anda.'; end if;
  return student.id;
end;
$$;

create or replace function public.authorize_user_management(p_actor_id uuid,p_profile jsonb,p_delete boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.profiles; u public.profiles; old public.profiles;
begin
  select * into a from public.profiles where id=p_actor_id;
  if a.id is null or not a.active then raise exception 'Akun pengelola tidak aktif.'; end if;
  u:=jsonb_populate_record(null::public.profiles,p_profile);
  if u.id is null or u.id=a.id then raise exception 'Gunakan menu profil untuk akun sendiri.'; end if;
  if a.role='developer' then
    if u.role not in ('admin','leader') or not exists(select 1 from public.tenants where id=u.tenant_id) then raise exception 'Developer hanya mengelola Admin dan Pimpinan instansi.'; end if;
  elsif a.role in ('admin','leader') then
    if not public.tenant_active(a.tenant_id) or u.tenant_id is distinct from a.tenant_id or (u.role not in ('teacher','student') and not (a.role='leader' and u.role='admin')) then raise exception 'Akses pengelolaan akun ditolak.'; end if;
  else raise exception 'Akses pengelolaan akun ditolak.'; end if;
  select * into old from public.profiles where id=u.id;
  if old.id is not null and (u.tenant_id is distinct from old.tenant_id or u.role is distinct from old.role or u.email is distinct from old.email) then raise exception 'Email, role, dan instansi akun tidak dapat diganti.'; end if;
  if coalesce(length(btrim(u.name)),0) not between 1 and 160 or coalesce(u.email,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Nama atau email belum valid.'; end if;
  if u.class_id is not null and (u.role<>'student' or not exists(select 1 from public.learning_entities e where e.id=u.class_id and e.tenant_id=u.tenant_id and e.kind='classroom')) then raise exception 'Kelas tidak valid.'; end if;
  if old.id is not null and old.class_id is distinct from u.class_id and exists(select 1 from public.learning_entities e where e.data->>'studentId'=u.id::text) then raise exception 'Siswa memiliki riwayat belajar. Kelas tidak dapat diganti.'; end if;
  if not u.active and exists(select 1 from public.learning_entities e where e.kind='classroom' and e.data->>'teacherId'=u.id::text) then raise exception 'Ganti guru pembimbing sebelum menonaktifkan akun.'; end if;
  if p_delete and exists(select 1 from public.learning_entities e where e.author_id=u.id or e.data->>'studentId'=u.id::text or e.data->>'teacherId'=u.id::text) then raise exception 'Akun memiliki riwayat. Nonaktifkan akun untuk mempertahankan data.'; end if;
end;
$$;

commit;
