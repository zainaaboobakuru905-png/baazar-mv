-- BazaarMV seller-specific manual BML payments.
-- Run once in Supabase SQL Editor after the existing marketplace/admin migrations.
-- Payment proof files are stored privately; this is NOT a BML gateway integration.

alter table public.seller_profiles
  add column if not exists bml_payment_instructions text not null default '';
alter table public.seller_profiles add column if not exists bml_qr_url text not null default '';

create table if not exists public.bazaar_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  transaction_reference text not null check (char_length(trim(transaction_reference)) between 1 and 120),
  proof_path text not null,
  status text not null default 'pending_review'
    check (status in ('pending_review','verified','rejected')),
  admin_note text not null default '',
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists bazaar_payment_seller_idx
  on public.bazaar_payment_submissions(seller_id, created_at desc);
alter table public.bazaar_payment_submissions enable row level security;

drop policy if exists "Buyer and seller read payment submissions" on public.bazaar_payment_submissions;
create policy "Buyer and seller read payment submissions"
on public.bazaar_payment_submissions for select to authenticated
using (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()));

-- Seller QR codes are intentionally public so buyers can scan the seller's payment QR.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('seller-bml-qr','seller-bml-qr',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=3145728,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Anyone can view seller BML QR codes" on storage.objects;
create policy "Anyone can view seller BML QR codes"
on storage.objects for select to anon,authenticated using (bucket_id='seller-bml-qr');

drop policy if exists "Approved sellers upload own BML QR" on storage.objects;
create policy "Approved sellers upload own BML QR"
on storage.objects for insert to authenticated with check (
  bucket_id='seller-bml-qr'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists (select 1 from public.seller_profiles sp
    where sp.user_id=(select auth.uid()) and sp.approval_status='approved')
);

drop policy if exists "Sellers update own BML QR" on storage.objects;
create policy "Sellers update own BML QR"
on storage.objects for update to authenticated using (
  bucket_id='seller-bml-qr' and (storage.foldername(name))[1]=(select auth.uid())::text
) with check (
  bucket_id='seller-bml-qr' and (storage.foldername(name))[1]=(select auth.uid())::text
);

drop policy if exists "Sellers delete own BML QR" on storage.objects;
create policy "Sellers delete own BML QR"
on storage.objects for delete to authenticated using (
  bucket_id='seller-bml-qr' and (storage.foldername(name))[1]=(select auth.uid())::text
);

-- Private bucket for payment screenshots. Never make this bucket public.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false, file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists "Buyers upload own payment proofs" on storage.objects;
create policy "Buyers upload own payment proofs"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.orders o
    where o.id::text = (storage.foldername(name))[2]
      and o.buyer_id = (select auth.uid())
  )
);

drop policy if exists "Buyer and admin read payment proofs" on storage.objects;
create policy "Buyer and admin read payment proofs"
on storage.objects for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.bazaar_admins a where a.user_id = (select auth.uid()))
  )
);

drop function if exists public.bazaar_seller_update_bml_instructions(text);
create or replace function public.bazaar_seller_update_bml_instructions(p_instructions text, p_qr_url text default '')
returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  if p_instructions is null or char_length(trim(p_instructions)) > 1000 then
    raise exception 'Payment instructions must be 1,000 characters or fewer.';
  end if;
  if p_qr_url is null or (trim(p_qr_url) <> '' and (char_length(trim(p_qr_url)) > 500 or trim(p_qr_url) !~ '^https://')) then
    raise exception 'QR image URL must be a valid HTTPS URL.';
  end if;
  update public.seller_profiles
     set bml_payment_instructions = trim(p_instructions), bml_qr_url = trim(coalesce(p_qr_url,''))
   where user_id = auth.uid() and approval_status = 'approved';
  if not found then raise exception 'An approved seller account is required.'; end if;
end;
$$;

create or replace function public.bazaar_buyer_submit_payment_proof(
  p_order_id uuid, p_reference text, p_proof_path text
) returns void language plpgsql security definer set search_path = public
as $$
declare v_order public.orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  if p_reference is null or char_length(trim(p_reference)) not between 1 and 120 then
    raise exception 'Enter a valid transaction reference.';
  end if;
  if p_proof_path is null or p_proof_path not like auth.uid()::text || '/' || p_order_id::text || '/%' then
    raise exception 'Invalid payment proof file path.';
  end if;
  select * into v_order from public.orders
   where id = p_order_id and buyer_id = auth.uid() for update;
  if not found then raise exception 'Order not found.'; end if;
  if v_order.status = 'Cancelled' then raise exception 'Cancelled orders cannot receive payment proof.'; end if;

  insert into public.bazaar_payment_submissions
    (order_id,buyer_id,seller_id,transaction_reference,proof_path,status,admin_note,reviewed_at,updated_at)
  values
    (v_order.id,v_order.buyer_id,v_order.seller_id,trim(p_reference),p_proof_path,'pending_review','',null,now())
  on conflict (order_id) do update set
    transaction_reference=excluded.transaction_reference,
    proof_path=excluded.proof_path,
    status='pending_review', admin_note='', reviewed_at=null, updated_at=now()
  where public.bazaar_payment_submissions.buyer_id = auth.uid()
    and public.bazaar_payment_submissions.status = 'rejected';
  if not found then raise exception 'Payment proof is already submitted or has been verified.'; end if;
end;
$$;

create or replace function public.bazaar_buyer_get_payment_instructions(p_order_id uuid)
returns table(order_id uuid, seller_name text, shop_name text, instructions text, qr_url text,
              payment_status text, transaction_reference text, admin_note text)
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  return query
    select o.id, coalesce(p.display_name,'Seller'), s.shop_name,
           s.bml_payment_instructions, s.bml_qr_url,
           coalesce(ps.status,'not_submitted'),
           coalesce(ps.transaction_reference,''),
           coalesce(ps.admin_note,'')
    from public.orders o
    join public.seller_profiles s on s.user_id=o.seller_id
    left join public.profiles p on p.id=o.seller_id
    left join public.bazaar_payment_submissions ps on ps.order_id=o.id
    where o.id=p_order_id and o.buyer_id=auth.uid();
end;
$$;

create or replace function public.bazaar_admin_list_payment_submissions()
returns table(submission_id uuid, order_id uuid, buyer_name text, shop_name text,
              total_mvr numeric, transaction_reference text, proof_path text,
              payment_status text, admin_note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.bazaar_admins a where a.user_id=auth.uid()
  ) then raise exception 'Administrator access required.'; end if;
  return query
    select ps.id, o.id, coalesce(b.display_name,'Buyer'), s.shop_name,
           o.total_mvr, ps.transaction_reference, ps.proof_path,
           ps.status, ps.admin_note, ps.created_at
    from public.bazaar_payment_submissions ps
    join public.orders o on o.id=ps.order_id
    left join public.profiles b on b.id=ps.buyer_id
    left join public.seller_profiles s on s.user_id=ps.seller_id
    order by ps.created_at desc;
end;
$$;

create or replace function public.bazaar_admin_review_payment(
  p_submission_id uuid, p_status text, p_note text default ''
) returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.bazaar_admins a where a.user_id=auth.uid()
  ) then raise exception 'Administrator access required.'; end if;
  if p_status not in ('verified','rejected') then raise exception 'Invalid payment review status.'; end if;
  if char_length(coalesce(p_note,'')) > 500 then raise exception 'Review note is too long.'; end if;
  update public.bazaar_payment_submissions
     set status=p_status, admin_note=trim(coalesce(p_note,'')),
         reviewed_at=now(), updated_at=now()
   where id=p_submission_id and status <> 'verified';
  if not found then raise exception 'Payment submission not found or already verified.'; end if;
end;
$$;

revoke all on function public.bazaar_seller_update_bml_instructions(text,text) from public;
revoke all on function public.bazaar_buyer_submit_payment_proof(uuid,text,text) from public;
revoke all on function public.bazaar_buyer_get_payment_instructions(uuid) from public;
revoke all on function public.bazaar_admin_list_payment_submissions() from public;
revoke all on function public.bazaar_admin_review_payment(uuid,text,text) from public;
grant execute on function public.bazaar_seller_update_bml_instructions(text,text) to authenticated;
grant execute on function public.bazaar_buyer_submit_payment_proof(uuid,text,text) to authenticated;
grant execute on function public.bazaar_buyer_get_payment_instructions(uuid) to authenticated;
grant execute on function public.bazaar_admin_list_payment_submissions() to authenticated;
grant execute on function public.bazaar_admin_review_payment(uuid,text,text) to authenticated;

-- Seller-controlled payment review: sellers can see and review only their own orders.
drop policy if exists "Buyer and admin read payment proofs" on storage.objects;
create policy "Buyer seller and admin read payment proofs"
on storage.objects for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.bazaar_payment_submissions ps
      where ps.proof_path = storage.objects.name
        and ps.seller_id = (select auth.uid())
    )
    or exists (select 1 from public.bazaar_admins a where a.user_id = (select auth.uid()))
  )
);

create or replace function public.bazaar_seller_list_payment_submissions()
returns table(submission_id uuid, order_id uuid, buyer_name text, total_mvr numeric,
              transaction_reference text, proof_path text, payment_status text,
              seller_note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  if not exists (select 1 from public.seller_profiles sp
                 where sp.user_id=auth.uid() and sp.approval_status='approved') then
    raise exception 'An approved seller account is required.';
  end if;
  return query
    select ps.id, o.id, coalesce(b.display_name,'Buyer'), o.total_mvr,
           ps.transaction_reference, ps.proof_path, ps.status, ps.admin_note, ps.created_at
    from public.bazaar_payment_submissions ps
    join public.orders o on o.id=ps.order_id
    left join public.profiles b on b.id=ps.buyer_id
    where ps.seller_id=auth.uid()
    order by ps.created_at desc;
end;
$$;

create or replace function public.bazaar_seller_review_payment(
  p_submission_id uuid, p_status text, p_note text default ''
) returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  if p_status not in ('verified','rejected') then raise exception 'Invalid payment review status.'; end if;
  if char_length(coalesce(p_note,'')) > 500 then raise exception 'Review note is too long.'; end if;
  if not exists (select 1 from public.seller_profiles sp
                 where sp.user_id=auth.uid() and sp.approval_status='approved') then
    raise exception 'An approved seller account is required.';
  end if;
  update public.bazaar_payment_submissions
     set status=p_status, admin_note=trim(coalesce(p_note,'')),
         reviewed_at=now(), updated_at=now()
   where id=p_submission_id and seller_id=auth.uid() and status <> 'verified';
  if not found then raise exception 'Payment submission not found, not yours, or already verified.'; end if;
end;
$$;

revoke all on function public.bazaar_seller_list_payment_submissions() from public;
revoke all on function public.bazaar_seller_review_payment(uuid,text,text) from public;
grant execute on function public.bazaar_seller_list_payment_submissions() to authenticated;
grant execute on function public.bazaar_seller_review_payment(uuid,text,text) to authenticated;
