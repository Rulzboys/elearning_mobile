-- DANA Payment Gateway sandbox. Requires 202609140001 and 202609140002.
begin;

create table public.spp_gateway_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null unique references public.tenants(id),
  enabled boolean not null default false,
  external_store_id text not null check (length(btrim(external_store_id)) between 1 and 64),
  contact_phone text not null default '',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.spp_gateway_settings enable row level security;
create policy spp_gateway_settings_read on public.spp_gateway_settings for select to authenticated
using (public.spp_read(tenant_id,null,false));
revoke all on public.spp_gateway_settings from public,anon,authenticated;
grant select on public.spp_gateway_settings to authenticated;
grant all on public.spp_gateway_settings to service_role;

alter table public.spp_payments alter column payload set default '';
alter table public.spp_payments alter column merchant_name set default 'DANA QRIS';
alter table public.spp_payments add column provider text not null default 'manual_qris';
alter table public.spp_payments add column partner_reference_no text;
alter table public.spp_payments add column provider_reference_no text;
alter table public.spp_payments add column provider_status text;
alter table public.spp_payments add column provider_response jsonb;
alter table public.spp_payments add column paid_at timestamptz;
create unique index spp_dana_partner_ref_once on public.spp_payments(partner_reference_no) where partner_reference_no is not null;
create unique index spp_dana_provider_ref_once on public.spp_payments(provider_reference_no) where provider_reference_no is not null;

create or replace function public.spp_gateway_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.profiles; cfg public.spp_gateway_settings; result jsonb;
begin
 a:=public.assert_active_actor();
 if a.role not in ('admin','leader') then raise exception 'Hanya Admin dan Pimpinan boleh mengatur Payment Gateway.'; end if;
 if p_action<>'settings' then raise exception 'Aksi gateway tidak dikenal.'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Data tidak valid.'; end if;
 if length(coalesce(p_data->>'contact_phone',''))>40 then raise exception 'Nomor kontak terlalu panjang.'; end if;
 insert into public.spp_gateway_settings(tenant_id,enabled,external_store_id,contact_phone,created_by)
 values(a.tenant_id,coalesce((p_data->>'enabled')::boolean,false),btrim(p_data->>'external_store_id'),
        btrim(coalesce(p_data->>'contact_phone','')),a.id)
 on conflict(tenant_id) do update set enabled=excluded.enabled,external_store_id=excluded.external_store_id,
 contact_phone=excluded.contact_phone,updated_at=now()
 returning to_jsonb(spp_gateway_settings.*) into result;
 insert into public.spp_audit(tenant_id,actor_id,action,record_id,after_data)
 values(a.tenant_id,a.id,'gateway_settings',a.tenant_id,result);
 return result;
end; $$;

-- Called with the end-user JWT by dana-create-payment. It validates the amount server-side.
create or replace function public.spp_dana_reserve(p_invoice_id uuid,p_amount integer,p_payment_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.profiles; i public.spp_invoices; pay public.spp_payments; cfg public.spp_gateway_settings;
 used bigint; ref text; result jsonb;
begin
 a:=public.assert_active_actor();
 if a.role<>'student' then raise exception 'Pembayaran hanya untuk akun wali/siswa.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(a.tenant_id::text,0));
 select * into i from public.spp_invoices where id=p_invoice_id and tenant_id=a.tenant_id and student_id=a.id and not archived;
 if i.id is null then raise exception 'Tagihan tidak tersedia.'; end if;
 select * into cfg from public.spp_gateway_settings where tenant_id=a.tenant_id and enabled;
 if cfg.tenant_id is null then raise exception 'Payment Gateway belum diaktifkan pengelola.'; end if;
 select coalesce(sum(amount),0) into used from public.spp_payments where invoice_id=i.id and status in ('reported','matched');
 if p_amount is null or p_amount not between 1 and 10000000 or p_amount>i.amount-used
    or (not i.allow_partial and p_amount<>i.amount-used) then raise exception 'Nominal tidak sesuai sisa tagihan atau aturan cicilan.'; end if;
 select * into pay from public.spp_payments where id=p_payment_id;
 if pay.id is not null then
   if pay.student_id<>a.id or pay.invoice_id<>i.id or pay.amount<>p_amount or pay.provider<>'dana' then
     raise exception 'ID pembayaran sudah digunakan.';
   end if;
   return to_jsonb(pay)||jsonb_build_object('external_store_id',cfg.external_store_id,'invoice_title',i.title);
 end if;
 select * into pay from public.spp_payments where invoice_id=i.id and provider='dana' and status='pending' and expires_at>now() order by created_at desc limit 1;
 if pay.id is not null then
   if pay.amount=p_amount then return to_jsonb(pay)||jsonb_build_object('external_store_id',cfg.external_store_id,'invoice_title',i.title); end if;
   raise exception 'Masih ada sesi pembayaran aktif.';
 end if;
 ref:='SPP'||left(replace(p_payment_id::text,'-',''),22);
 insert into public.spp_payments(id,tenant_id,invoice_id,student_id,amount,payload,merchant_name,status,provider,
   partner_reference_no,created_by,expires_at,contact_phone)
 values(p_payment_id,a.tenant_id,i.id,a.id,p_amount,'','DANA QRIS','pending','dana',ref,a.id,now()+interval '5 minutes',cfg.contact_phone)
 returning to_jsonb(spp_payments.*) into result;
 return result||jsonb_build_object('external_store_id',cfg.external_store_id,'invoice_title',i.title);
end; $$;

create or replace function public.spp_dana_created(p_payment_id uuid,p_payment_code text,p_reference_no text,p_response jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required.'; end if;
 if length(coalesce(p_payment_code,'')) not between 20 and 4096 then raise exception 'QR pembayaran DANA tidak valid.'; end if;
 update public.spp_payments set payload=p_payment_code,provider_reference_no=nullif(p_reference_no,''),provider_status='CREATED',provider_response=p_response
 where id=p_payment_id and provider='dana' and status='pending' returning to_jsonb(spp_payments.*) into result;
 if result is null then raise exception 'Transaksi tidak ditemukan.'; end if;
 return result;
end; $$;

create or replace function public.spp_dana_notify(p_partner_ref text,p_reference_no text,p_merchant_id text,
 p_amount integer,p_currency text,p_status text,p_finished_at timestamptz,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pay public.spp_payments; result jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_partner_ref,0));
 select * into pay from public.spp_payments where partner_reference_no=p_partner_ref and provider='dana';
 if pay.id is null or pay.amount<>p_amount or p_currency<>'IDR' then raise exception 'Notifikasi tidak cocok dengan transaksi.'; end if;
 if pay.provider_reference_no is not null and pay.provider_reference_no<>p_reference_no then raise exception 'Referensi DANA tidak cocok.'; end if;
 if p_status='00' then
   update public.spp_payments set status='matched',provider_status='00',provider_reference_no=p_reference_no,
     bank_reference=p_reference_no,paid_at=coalesce(p_finished_at,now()),reviewed_at=now(),review_note='Terverifikasi otomatis oleh webhook DANA',provider_response=p_payload
   where id=pay.id returning to_jsonb(spp_payments.*) into result;
 elsif p_status='05' and pay.status='pending' then
   update public.spp_payments set provider_status='05',provider_reference_no=p_reference_no,provider_response=p_payload
   where id=pay.id returning to_jsonb(spp_payments.*) into result;
 else
   update public.spp_payments set provider_status=p_status,provider_response=p_payload where id=pay.id
   returning to_jsonb(spp_payments.*) into result;
 end if;
 insert into public.spp_audit(tenant_id,actor_id,action,record_id,before_data,after_data)
 values(pay.tenant_id,pay.student_id,'dana_notify',pay.id,to_jsonb(pay),result);
 return result;
end; $$;

revoke all on function public.spp_gateway_action(text,jsonb),public.spp_dana_reserve(uuid,integer,uuid),
 public.spp_dana_created(uuid,text,text,jsonb),public.spp_dana_notify(text,text,text,integer,text,text,timestamptz,jsonb)
 from public,anon,authenticated;
grant execute on function public.spp_gateway_action(text,jsonb),public.spp_dana_reserve(uuid,integer,uuid) to authenticated;
grant execute on function public.spp_dana_created(uuid,text,text,jsonb),public.spp_dana_notify(text,text,text,integer,text,text,timestamptz,jsonb) to service_role;
notify pgrst, 'reload schema';
commit;
