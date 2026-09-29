-- Requires 202609080001 + 202609140001. No destructive reset and no Auth users created.
begin;
create table public.spp_qris_settings (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null unique references public.tenants(id),
 payload text not null, merchant_name text not null, enabled boolean not null default false,
 nominal_enabled boolean not null default false, contact_phone text not null default '',
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.spp_invoices (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
 student_id uuid not null references public.profiles(id), title text not null check(length(btrim(title)) between 1 and 160),
 period text not null check(length(btrim(period)) between 1 and 60), amount integer not null check(amount between 1 and 1000000000),
 due_date date not null, allow_partial boolean not null default true, archived boolean not null default false,
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 unique(tenant_id, student_id, title, period)
);
create table public.spp_payments (
 id uuid primary key, tenant_id uuid not null references public.tenants(id),
 invoice_id uuid not null references public.spp_invoices(id), student_id uuid not null references public.profiles(id),
 amount integer not null check(amount between 1 and 10000000), payload text not null, merchant_name text not null,
 status text not null default 'pending' check(status in ('pending','reported','matched','disputed')),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 expires_at timestamptz not null, reported_at timestamptz, payer_name text not null default '',
 transfer_reference text not null default '', reported_late boolean not null default false,
 reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
 bank_reference text, review_note text not null default '', contact_phone text not null default ''
);
create unique index spp_bank_reference_once on public.spp_payments(tenant_id,bank_reference) where status='matched';
create index spp_invoice_student_idx on public.spp_invoices(tenant_id,student_id);
create index spp_payment_invoice_idx on public.spp_payments(tenant_id,invoice_id,status);
create table public.spp_audit (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
 actor_id uuid not null references public.profiles(id), action text not null, record_id uuid not null,
 before_data jsonb, after_data jsonb, created_at timestamptz not null default now()
);

create function public.spp_read(p_tenant uuid,p_student uuid default null,p_managers_only boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles a where a.id=auth.uid() and a.active and
 a.tenant_id=p_tenant and public.tenant_active(a.tenant_id) and
 (a.role in ('admin','leader') or (not p_managers_only and a.role='student' and a.id=p_student)));
$$;
alter table public.spp_qris_settings enable row level security;
alter table public.spp_invoices enable row level security;
alter table public.spp_payments enable row level security;
alter table public.spp_audit enable row level security;
create policy spp_settings_read on public.spp_qris_settings for select to authenticated using(public.spp_read(tenant_id,null,true));
create policy spp_invoice_read on public.spp_invoices for select to authenticated using(public.spp_read(tenant_id,student_id));
create policy spp_payment_read on public.spp_payments for select to authenticated using(public.spp_read(tenant_id,student_id));
create policy spp_audit_read on public.spp_audit for select to authenticated using(public.spp_read(tenant_id,null,true));
revoke all on public.spp_qris_settings, public.spp_invoices, public.spp_payments, public.spp_audit from public,anon,authenticated;
grant select on public.spp_qris_settings, public.spp_invoices, public.spp_payments, public.spp_audit to authenticated;
grant all on public.spp_qris_settings, public.spp_invoices, public.spp_payments, public.spp_audit to service_role;

create function public.spp_crc(p_text text) returns text language plpgsql immutable set search_path='' as $$
declare c integer:=65535; i integer; j integer;
begin
 for i in 1..length(p_text) loop
  c:=c # (ascii(substr(p_text,i,1)) << 8);
  for j in 1..8 loop
   c:=(case when (c & 32768)<>0 then (c << 1) # 4129 else c << 1 end) & 65535;
  end loop;
 end loop;
 return upper(lpad(to_hex(c),4,'0'));
end; $$;

create function public.spp_qris_fields(p_raw text) returns jsonb language plpgsql immutable set search_path='' as $$
declare f jsonb:='{}'; pos integer:=1; tag text; len integer; last_tag text; has_merchant boolean:=false;
begin
 if p_raw is null or length(p_raw) not between 40 and 2048 or p_raw ~ '[^ -~]' then raise exception 'Payload QRIS tidak valid.'; end if;
 while pos<=length(p_raw) loop
  tag:=substr(p_raw,pos,2);
  if tag !~ '^[0-9]{2}$' or substr(p_raw,pos+2,2) !~ '^[0-9]{2}$' then raise exception 'Format TLV QRIS tidak valid.'; end if;
  len:=substr(p_raw,pos+2,2)::integer;
  if len<1 or pos+3+len>length(p_raw) or f ? tag then raise exception 'Struktur QRIS tidak valid.'; end if;
  f:=f||jsonb_build_object(tag,substr(p_raw,pos+4,len));
  if tag::int between 26 and 51 then has_merchant:=true; end if;
  last_tag:=tag; pos:=pos+4+len;
 end loop;
 if f->>'00' is distinct from '01' or coalesce(f->>'01','') not in ('11','12') or f->>'53' is distinct from '360' or
 f->>'58' is distinct from 'ID' or coalesce(length(btrim(f->>'59')),0)=0 or coalesce(length(btrim(f->>'60')),0)=0 or
 not (f ? '52') or not has_merchant or last_tag<>'63' or length(f->>'63')<>4 or
 f->>'63'<>public.spp_crc(left(p_raw,length(p_raw)-4)) then raise exception 'QRIS merchant IDR/Indonesia atau CRC tidak valid.'; end if;
 return f;
end; $$;

create function public.spp_qris_static(p_raw text) returns text language plpgsql immutable set search_path='' as $$
declare f jsonb:=public.spp_qris_fields(p_raw);
begin
 if f->>'01'<>'11' or f ?| array['54','55','56','57'] then raise exception 'Gunakan QRIS statis tanpa nominal, tip, atau biaya tambahan.'; end if;
 return f->>'59';
end; $$;
create function public.spp_qris_amount(p_raw text,p_amount integer) returns text language plpgsql immutable set search_path='' as $$
declare f jsonb; r record; body text:='';
begin
 perform public.spp_qris_static(p_raw);
 if p_amount is null or p_amount not between 1 and 10000000 then raise exception 'Nominal harus Rp1 sampai Rp10.000.000.'; end if;
 f:=(public.spp_qris_fields(p_raw)-'63')||jsonb_build_object('01','12','54',p_amount::text);
 for r in select key,value from jsonb_each_text(f) order by key loop
  body:=body||r.key||lpad(length(r.value)::text,2,'0')||r.value;
 end loop;
 body:=body||'6304'; return body||public.spp_crc(body);
end; $$;

-- Only RPC can change billing data. auth.uid(), tenant, amount and QR are server-controlled.
create function public.spp_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.profiles; i public.spp_invoices; pay public.spp_payments; settings public.spp_qris_settings;
 old_data jsonb; result jsonb; ident uuid; n integer; used bigint; manager boolean; merchant text;
begin
 a:=public.assert_active_actor();
 manager:=a.role in ('admin','leader');
 if a.role not in ('admin','leader','student') then raise exception 'Akses SPP ditolak.'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>12000 then raise exception 'Data tidak valid.'; end if;
 -- Serialize per-tenant mutations, including invoice totals, duplicate reports and reconciliation.
 perform pg_advisory_xact_lock(hashtextextended(a.tenant_id::text,0));
 if p_action='settings' then
  if not manager then raise exception 'Hanya Admin dan Pimpinan boleh mengatur QRIS.'; end if;
  merchant:=public.spp_qris_static(btrim(p_data->>'payload'));
  if coalesce(p_data->>'consent','')<>'true' then raise exception 'Konfirmasi kewenangan merchant dan dukungan penyedia terlebih dahulu.'; end if;
  if length(coalesce(p_data->>'contact_phone',''))>40 then raise exception 'Nomor kontak terlalu panjang.'; end if;
  select to_jsonb(s) into old_data from public.spp_qris_settings s where tenant_id=a.tenant_id;
  insert into public.spp_qris_settings(tenant_id,payload,merchant_name,enabled,nominal_enabled,contact_phone,created_by)
  values(a.tenant_id,btrim(p_data->>'payload'),merchant,coalesce((p_data->>'enabled')::boolean,false),
  coalesce((p_data->>'nominal_enabled')::boolean,false),coalesce(p_data->>'contact_phone',''),a.id)
  on conflict(tenant_id) do update set payload=excluded.payload,merchant_name=excluded.merchant_name,enabled=excluded.enabled,
  nominal_enabled=excluded.nominal_enabled,contact_phone=excluded.contact_phone,updated_at=now() returning to_jsonb(spp_qris_settings.*) into result;
 elsif p_action='invoice' then
  if not manager then raise exception 'Hanya pengelola boleh mengatur tagihan.'; end if;
  ident:=(p_data->>'id')::uuid;
  if ident is null then raise exception 'ID wajib diisi.'; end if;
  select * into i from public.spp_invoices where id=ident;
  old_data:=case when i.id is not null then to_jsonb(i) end;
  if i.id is not null and (i.tenant_id<>a.tenant_id or i.student_id::text is distinct from p_data->>'student_id') then raise exception 'Siswa atau instansi tagihan tidak dapat diganti.'; end if;
  if exists(select 1 from public.spp_payments where invoice_id=ident) then raise exception 'Tagihan memiliki transaksi; tidak dapat diubah. Gunakan arsip.'; end if;
  if not exists(select 1 from public.profiles where id=(p_data->>'student_id')::uuid and tenant_id=a.tenant_id and role='student' and active) then raise exception 'Pilih siswa aktif dari instansi yang sama.'; end if;
  insert into public.spp_invoices(id,tenant_id,student_id,title,period,amount,due_date,allow_partial,created_by)
  values(ident,a.tenant_id,(p_data->>'student_id')::uuid,btrim(p_data->>'title'),btrim(p_data->>'period'),
  (p_data->>'amount')::integer,(p_data->>'due_date')::date,coalesce((p_data->>'allow_partial')::boolean,true),a.id)
  on conflict(id) do update set title=excluded.title,period=excluded.period,amount=excluded.amount,due_date=excluded.due_date,allow_partial=excluded.allow_partial
  returning to_jsonb(spp_invoices.*) into result;
 elsif p_action='archive' then
  if not manager then raise exception 'Akses ditolak.'; end if;
  select * into i from public.spp_invoices where id=(p_data->>'id')::uuid and tenant_id=a.tenant_id;
  if i.id is null then raise exception 'Tagihan tidak ditemukan.'; end if;
  old_data:=to_jsonb(i);
  update public.spp_invoices set archived=not archived where id=i.id returning to_jsonb(spp_invoices.*) into result;
 elsif p_action='checkout' then
  if a.role<>'student' then raise exception 'Checkout hanya untuk akun wali/siswa.'; end if;
  ident:=(p_data->>'id')::uuid;
  select * into pay from public.spp_payments where id=ident;
  if pay.id is not null then
   if pay.student_id<>a.id or pay.tenant_id<>a.tenant_id or pay.invoice_id::text is distinct from p_data->>'invoice_id' or pay.amount is distinct from (p_data->>'amount')::integer then raise exception 'ID pembayaran sudah digunakan.'; end if;
   return to_jsonb(pay);
  end if;
  select * into i from public.spp_invoices where id=(p_data->>'invoice_id')::uuid and tenant_id=a.tenant_id and student_id=a.id and not archived;
  if i.id is null then raise exception 'Tagihan tidak tersedia.'; end if;
  n:=(p_data->>'amount')::integer;
  select coalesce(sum(amount),0) into used from public.spp_payments where invoice_id=i.id and status in ('reported','matched');
  if n is null or n not between 1 and 10000000 or n>i.amount-used or (not i.allow_partial and n<>i.amount-used) then raise exception 'Nominal tidak sesuai sisa tagihan atau aturan cicilan.'; end if;
  select * into pay from public.spp_payments where invoice_id=i.id and status='pending' and expires_at>now() order by created_at desc limit 1;
  if pay.id is not null then
   if pay.amount=n then return to_jsonb(pay); end if;
   raise exception 'Masih ada sesi QR aktif. Buka transaksi tersebut atau tunggu sesi berakhir.';
  end if;
  select * into settings from public.spp_qris_settings where tenant_id=a.tenant_id and enabled;
  if settings.id is null then raise exception 'QRIS belum diaktifkan pengelola.'; end if;
  insert into public.spp_payments(id,tenant_id,invoice_id,student_id,amount,payload,merchant_name,created_by,expires_at,contact_phone)
  values(ident,a.tenant_id,i.id,a.id,n,case when settings.nominal_enabled then public.spp_qris_amount(settings.payload,n) else settings.payload end,
  settings.merchant_name,a.id,now()+interval '5 minutes',settings.contact_phone) returning to_jsonb(spp_payments.*) into result;
 elsif p_action in ('report','reconcile') then
  select * into pay from public.spp_payments where id=(p_data->>'id')::uuid and tenant_id=a.tenant_id;
  if pay.id is null then raise exception 'Transaksi tidak ditemukan.'; end if;
  old_data:=to_jsonb(pay);
  if p_action='report' then
   if a.role<>'student' or pay.student_id<>a.id then raise exception 'Transaksi bukan milik akun ini.'; end if;
   if pay.status in ('reported','matched') then return to_jsonb(pay); end if;
   if pay.status<>'pending' then raise exception 'Hubungi pengelola untuk klarifikasi transaksi ini.'; end if;
   if coalesce(length(btrim(p_data->>'payer_name')),0) not between 1 and 160 or coalesce(length(btrim(p_data->>'transfer_reference')),0) not between 1 and 160 then raise exception 'Nama pembayar dan referensi transaksi wajib diisi.'; end if;
  elsif not manager or coalesce(p_data->>'status','') not in ('matched','disputed') or coalesce(length(btrim(p_data->>'review_note')),0) not between 1 and 500 then
   raise exception 'Hasil pengecekan dan catatan wajib diisi oleh pengelola.';
  end if;
  if p_action='report' or p_data->>'status'='matched' then
   select * into i from public.spp_invoices where id=pay.invoice_id;
   select coalesce(sum(amount),0) into used from public.spp_payments where invoice_id=i.id and id<>pay.id and status in ('reported','matched');
   if used+pay.amount>i.amount then raise exception 'Total melebihi tagihan. Hubungi pengelola untuk pencocokan mutasi.'; end if;
  end if;
  if p_action='report' then
   update public.spp_payments set status='reported',reported_at=now(),reported_late=now()>expires_at,
   payer_name=btrim(p_data->>'payer_name'),transfer_reference=btrim(p_data->>'transfer_reference') where id=pay.id
   returning to_jsonb(spp_payments.*) into result;
  else
   if p_data->>'status'='matched' and coalesce(length(btrim(p_data->>'bank_reference')),0) not between 1 and 160 then raise exception 'Referensi mutasi bank wajib diisi untuk dana yang cocok.'; end if;
   update public.spp_payments set status=p_data->>'status',reviewed_by=a.id,reviewed_at=now(),review_note=btrim(p_data->>'review_note'),
   bank_reference=case when p_data->>'status'='matched' then btrim(p_data->>'bank_reference') else null end
   where id=pay.id returning to_jsonb(spp_payments.*) into result;
  end if;
 else raise exception 'Aksi SPP tidak dikenal.'; end if;
 insert into public.spp_audit(tenant_id,actor_id,action,record_id,before_data,after_data)
 values(a.tenant_id,a.id,p_action,(result->>'id')::uuid,old_data,result);
 return result;
exception when unique_violation then raise exception 'Tagihan atau referensi mutasi sudah digunakan. Periksa riwayat sebelum mengulang.';
end; $$;

revoke all on function public.spp_read(uuid,uuid,boolean), public.spp_crc(text), public.spp_qris_fields(text), public.spp_qris_static(text), public.spp_qris_amount(text,integer), public.spp_action(text,jsonb) from public, anon, authenticated;
grant execute on function public.spp_read(uuid,uuid,boolean),public.spp_action(text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
