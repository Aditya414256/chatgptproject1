-- New schema for FindMedicine. Review conflicts before applying to an existing database.
create extension if not exists pgcrypto;
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', phone text not null default '',
 role text not null check(role in ('customer','store_owner')),
 created_at timestamptz not null default now()
);
create table if not exists public.stores(
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null unique references public.profiles(id),
 name text not null, address text not null,
 lat double precision not null check(lat between -90 and 90),
 lng double precision not null check(lng between -180 and 180),
 is_open boolean not null default true,
 offers_delivery boolean not null default false,
 serviceable_pincodes text[] not null default '{}'
);
create table if not exists public.medicines(
 id uuid primary key default gen_random_uuid(),name text not null unique,
 generic_name text,strength text,form text,
 requires_prescription boolean not null default false
);
create table if not exists public.store_inventory(
 store_id uuid not null references public.stores(id) on delete cascade,
 medicine_id uuid not null references public.medicines(id),
 price numeric(12,2) not null check(price>=0),stock integer not null check(stock>=0),
 primary key(store_id,medicine_id)
);
create table if not exists public.orders(
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.profiles(id),
 store_id uuid not null references public.stores(id),
 fulfilment_type text not null check(fulfilment_type in ('pickup','delivery')),
 status text not null default 'pending' check(status in('pending','accepted','rejected','cancelled','expired','ready','out_for_delivery','completed','not_collected')),
 delivery_address text,delivery_pincode text,prescription_path text,
 reject_reason text,handover_code text not null check(handover_code ~ '^\d{4}$'),
 total numeric(12,2) not null check(total>=0),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default(now()+interval '10 minutes'),
 check ((fulfilment_type='pickup' and delivery_address is null and delivery_pincode is null and prescription_path is null) or (fulfilment_type='delivery' and length(trim(delivery_address))>0 and delivery_pincode ~ '^\d{6}$'))
);
create index if not exists idx_orders_store on public.orders(store_id,created_at desc);
create index if not exists idx_orders_customer on public.orders(customer_id,created_at desc);
create table if not exists public.order_items(
 order_id uuid not null references public.orders(id) on delete cascade,
 medicine_id uuid not null references public.medicines(id),
 quantity integer not null check(quantity>0),unit_price numeric(12,2) not null check(unit_price>=0),
 primary key(order_id,medicine_id)
);
create table if not exists public.notifications(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),
 order_id uuid not null references public.orders(id),message text not null,
 read boolean not null default false,created_at timestamptz not null default now()
);

-- Signups are the only allowed source of profile role. Clients cannot later change it.
create or replace function public.create_signup_profile() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_role text;
begin
 v_role:=new.raw_user_meta_data->>'role';
 if v_role not in ('customer','store_owner') then raise exception 'Choose a valid role';end if;
 insert into public.profiles(id,full_name,phone,role) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.raw_user_meta_data->>'phone',''),v_role)
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_findmedicine_auth_user on auth.users;
create trigger on_findmedicine_auth_user after insert on auth.users for each row execute function public.create_signup_profile();
create or replace function public.protect_profile_role() returns trigger language plpgsql as $$ begin
 if new.role is distinct from old.role or new.id is distinct from old.id then raise exception 'Account role cannot be changed'; end if; return new;
end $$;
drop trigger if exists protect_findmedicine_role on public.profiles;
create trigger protect_findmedicine_role before update on public.profiles for each row execute function public.protect_profile_role();

-- One owner owns a single store; owner may edit only permitted fields through RLS.
alter table public.profiles enable row level security;
alter table public.stores enable row level security;
alter table public.medicines enable row level security;
alter table public.store_inventory enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.notifications enable row level security;
create policy "profiles self and customers in own store orders" on public.profiles for select to authenticated using(
 id=auth.uid() or exists(select 1 from public.orders o join public.stores s on s.id=o.store_id where o.customer_id=profiles.id and s.owner_id=auth.uid())
);
create policy "profiles self update" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "stores can be read by authenticated" on public.stores for select to authenticated using(true);
create policy "owner update own store" on public.stores for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy "catalog read" on public.medicines for select to authenticated using(true);
create policy "inventory read" on public.store_inventory for select to authenticated using(true);
create policy "owner edits inventory" on public.store_inventory for update to authenticated using(exists(select 1 from public.stores s where s.id=store_id and s.owner_id=auth.uid())) with check(exists(select 1 from public.stores s where s.id=store_id and s.owner_id=auth.uid()));
create policy "orders customer or store owner read" on public.orders for select to authenticated using(customer_id=auth.uid() or exists(select 1 from public.stores s where s.id=store_id and s.owner_id=auth.uid()));
create policy "order items customer or owner read" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and (o.customer_id=auth.uid() or exists(select 1 from public.stores s where s.id=o.store_id and s.owner_id=auth.uid()))));
create policy "notification self read" on public.notifications for select to authenticated using(user_id=auth.uid());
create policy "notification self mark read" on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
-- No direct client inserts, deletes or status updates on orders: use security-definer RPC.
revoke all on public.orders,public.order_items from anon,authenticated;
grant select on public.orders,public.order_items to authenticated;
revoke all on public.notifications from anon,authenticated;
grant select on public.notifications to authenticated;
grant update(read) on public.notifications to authenticated;
revoke insert,delete on public.store_inventory from authenticated;
revoke update on public.store_inventory from authenticated;
grant update(price,stock) on public.store_inventory to authenticated;
revoke insert,delete on public.medicines from authenticated;

-- Distance calculation and stock summary. Location arguments are never stored.
create or replace function public.nearby_stores(user_lat double precision,user_lng double precision,radius_km double precision,medicine_ids uuid[])
returns table(id uuid,name text,address text,is_open boolean,offers_delivery boolean,distance_km double precision,missing_items text[],total_price numeric)
language sql stable security definer set search_path=public,pg_temp as $$
 with candidates as (
 select s.*, 6371.0088*2*asin(least(1,sqrt(power(sin(radians(s.lat-user_lat)/2),2)+cos(radians(user_lat))*cos(radians(s.lat))*power(sin(radians(s.lng-user_lng)/2),2)))) as km
 from public.stores s where auth.uid() is not null and radius_km between 0 and 100 and user_lat between -90 and 90 and user_lng between -180 and 180
 ), aggregate as (
 select c.id,c.name,c.address,c.is_open,c.offers_delivery,c.km,
 coalesce(array_agg(m.name order by m.name) filter(where (si.stock is null or si.stock<1)),array[]::text[]) as missing,
 sum(case when si.stock>0 then si.price else 0 end) as total
 from candidates c cross join unnest(medicine_ids) requested(mid)
 join public.medicines m on m.id=requested.mid
 left join public.store_inventory si on si.store_id=c.id and si.medicine_id=m.id
 where c.km<=radius_km
 group by c.id,c.name,c.address,c.is_open,c.offers_delivery,c.km
 ) select a.id,a.name,a.address,a.is_open,a.offers_delivery,a.km,a.missing,a.total from aggregate a order by cardinality(a.missing),a.km;
$$;
create or replace function public.stores_for_pincode(pincode text,medicine_ids uuid[])
returns table(id uuid,name text,address text,is_open boolean,offers_delivery boolean,distance_km double precision,missing_items text[],total_price numeric)
language sql stable security definer set search_path=public,pg_temp as $$
 select s.id,s.name,s.address,s.is_open,s.offers_delivery,null::double precision,
 coalesce(array_agg(m.name order by m.name) filter(where (si.stock is null or si.stock<1)),array[]::text[]),
 sum(case when si.stock>0 then si.price else 0 end)
 from public.stores s cross join unnest(medicine_ids) req(mid) join public.medicines m on m.id=req.mid
 left join public.store_inventory si on si.store_id=s.id and si.medicine_id=m.id
 where auth.uid() is not null and s.offers_delivery and pincode=any(s.serviceable_pincodes)
 group by s.id,s.name,s.address,s.is_open,s.offers_delivery order by cardinality(coalesce(array_agg(m.name) filter(where si.stock is null or si.stock<1),array[]::text[])),s.name;
$$;

-- Order state transition enforcement and refund on nonfulfilled cancellation.
create or replace function public.enforce_order_status() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if new.status=old.status then
   if row(new.*) is distinct from row(old.*) then raise exception 'Order fields are immutable'; end if;
   return new;
 end if;
 if (old.status='pending' and new.status in('accepted','rejected','cancelled','expired'))
 or (old.status='accepted' and new.status in('ready','out_for_delivery','cancelled'))
 or (old.status in('ready','out_for_delivery') and new.status in('completed','not_collected')) then
   if new.status='ready' and old.fulfilment_type<>'pickup' or new.status='out_for_delivery' and old.fulfilment_type<>'delivery' then raise exception 'Wrong fulfilment transition';end if;
   if new.status in('rejected','cancelled','expired') then
     update public.store_inventory si set stock=si.stock+oi.quantity from public.order_items oi where oi.order_id=old.id and si.store_id=old.store_id and si.medicine_id=oi.medicine_id;
   end if;
   return new;
 end if;
 raise exception 'Invalid order status transition % -> %',old.status,new.status;
end $$;
drop trigger if exists validate_findmedicine_order_status on public.orders;
create trigger validate_findmedicine_order_status before update on public.orders for each row execute function public.enforce_order_status();

create or replace function public.place_order(
 p_store_id uuid,p_fulfilment_type text,p_items jsonb,
 p_delivery_address text default null,p_delivery_pincode text default null,p_prescription_path text default null
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid();v_role text;v_store public.stores%rowtype;v_item record;v_inv public.store_inventory%rowtype;v_total numeric:=0;v_id uuid;v_requires_rx boolean:=false;v_cnt int;v_dist int;
begin
 if v_user is null then raise exception 'Sign in required';end if;
 select role into v_role from public.profiles where id=v_user;
 if v_role is distinct from 'customer' then raise exception 'Only customers can order';end if;
 if p_fulfilment_type not in('pickup','delivery') then raise exception 'Invalid fulfilment';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Invalid cart';end if;
 select * into v_store from public.stores where id=p_store_id;
 if not found or not v_store.is_open then raise exception 'Store unavailable';end if;
 if p_fulfilment_type='delivery' then
   if not v_store.offers_delivery or p_delivery_pincode is null or not p_delivery_pincode=any(v_store.serviceable_pincodes) then raise exception 'Delivery not supported';end if;
   if coalesce(length(trim(p_delivery_address)),0)<5 then raise exception 'Enter a delivery address';end if;
 else
   if p_prescription_path is not null then raise exception 'Pickup does not need uploaded prescription';end if;
   if p_delivery_address is not null or p_delivery_pincode is not null then raise exception 'Pickup cannot include delivery address';end if;
 end if;
 select count(*),count(distinct x.medicine_id) into v_cnt,v_dist from jsonb_to_recordset(p_items) as x(medicine_id uuid,quantity int);
 if v_cnt<>v_dist then raise exception 'Duplicate medicine';end if;
 for v_item in select x.medicine_id,x.quantity,m.requires_prescription from jsonb_to_recordset(p_items) x(medicine_id uuid,quantity int) join public.medicines m on m.id=x.medicine_id order by x.medicine_id loop
   if v_item.quantity is null or v_item.quantity<1 or v_item.quantity>100 then raise exception 'Invalid quantity';end if;
   select * into v_inv from public.store_inventory where store_id=p_store_id and medicine_id=v_item.medicine_id for update;
   if not found or v_inv.stock<v_item.quantity then raise exception 'Insufficient stock';end if;
   v_total:=v_total+(v_inv.price*v_item.quantity);
   v_requires_rx:=v_requires_rx or v_item.requires_prescription;
 end loop;
 if v_cnt<>(select count(*) from jsonb_to_recordset(p_items) x(medicine_id uuid,quantity int) join public.medicines m on m.id=x.medicine_id) then raise exception 'Unknown medicine';end if;
 if p_fulfilment_type='delivery' and v_requires_rx and (p_prescription_path is null or p_prescription_path not like v_user::text||'/%') then raise exception 'Valid prescription upload required';end if;
 if p_prescription_path is not null and p_prescription_path not like v_user::text||'/%' then raise exception 'Invalid prescription path';end if;
 if p_prescription_path is not null and not exists(select 1 from storage.objects where bucket_id='prescriptions' and name=p_prescription_path and owner_id=v_user::text) then raise exception 'Prescription file not uploaded';end if;
 insert into public.orders(customer_id,store_id,fulfilment_type,delivery_address,delivery_pincode,prescription_path,handover_code,total)
 values(v_user,p_store_id,p_fulfilment_type,case when p_fulfilment_type='delivery' then p_delivery_address end,case when p_fulfilment_type='delivery' then p_delivery_pincode end,p_prescription_path,lpad(floor(random()*10000)::int::text,4,'0'),v_total) returning id into v_id;
 for v_item in select x.medicine_id,x.quantity from jsonb_to_recordset(p_items) x(medicine_id uuid,quantity int) order by x.medicine_id loop
   insert into public.order_items(order_id,medicine_id,quantity,unit_price) select v_id,v_item.medicine_id,v_item.quantity,price from public.store_inventory where store_id=p_store_id and medicine_id=v_item.medicine_id;
   update public.store_inventory set stock=stock-v_item.quantity where store_id=p_store_id and medicine_id=v_item.medicine_id;
 end loop;
 insert into public.notifications(user_id,order_id,message) values(v_store.owner_id,v_id,'New order received');
 return v_id;
end $$;

create or replace function public.update_order_status(p_order_id uuid,p_new_status text,p_code text default null,p_reject_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare o public.orders%rowtype;v_owner uuid;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found';end if;
 select owner_id into v_owner from public.stores where id=o.store_id;
 if p_new_status='cancelled' and o.status='pending' and auth.uid()=o.customer_id then null;
 elsif auth.uid()=v_owner and p_new_status in('accepted','rejected','ready','out_for_delivery','completed','not_collected') then null;
 else raise exception 'Action not permitted';end if;
 if p_new_status='completed' and (p_code is null or p_code<>o.handover_code) then raise exception 'Incorrect handover code';end if;
 update public.orders set status=p_new_status,reject_reason=case when p_new_status='rejected' then coalesce(nullif(trim(p_reject_reason),''),'No reason supplied') else reject_reason end where id=p_order_id;
 insert into public.notifications(user_id,order_id,message) values(o.customer_id,o.id,'Order status: '||p_new_status);
end $$;
revoke all on function public.place_order(uuid,text,jsonb,text,text,text) from public,anon;
grant execute on function public.place_order(uuid,text,jsonb,text,text,text) to authenticated;
revoke all on function public.update_order_status(uuid,text,text,text) from public,anon;
grant execute on function public.update_order_status(uuid,text,text,text) to authenticated;
revoke all on function public.nearby_stores(double precision,double precision,double precision,uuid[]) from public,anon;
grant execute on function public.nearby_stores(double precision,double precision,double precision,uuid[]) to authenticated;
revoke all on function public.stores_for_pincode(text,uuid[]) from public,anon;
grant execute on function public.stores_for_pincode(text,uuid[]) to authenticated;

-- Storage bucket already exists; create policies without replacing the bucket.
do $$begin
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='findmedicine customer uploads') then
 execute $policy$create policy "findmedicine customer uploads" on storage.objects for insert to authenticated with check(bucket_id='prescriptions' and (storage.foldername(name))[1]=auth.uid()::text)$policy$;
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='findmedicine prescription reads') then
 execute $policy$create policy "findmedicine prescription reads" on storage.objects for select to authenticated using(bucket_id='prescriptions' and (owner_id=auth.uid()::text or exists(select 1 from public.orders o join public.stores s on s.id=o.store_id where o.prescription_path=name and s.owner_id=auth.uid())))$policy$;
 end if;
end $$;

-- Expiry worker can be invoked by pg_cron with a scheduled task.
create or replace function public.expire_findmedicine_orders() returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update public.orders set status='expired' where status='pending' and expires_at<=now();
end $$;
revoke all on function public.expire_findmedicine_orders() from public,anon,authenticated;
-- If pg_cron is installed, schedule once. (pg_cron extension should already exist.)
do $$begin
 if exists(select 1 from pg_extension where extname='pg_cron') and not exists(select 1 from cron.job where jobname='findmedicine-expire-orders') then
 perform cron.schedule('findmedicine-expire-orders','* * * * *','select public.expire_findmedicine_orders()');
 end if;
exception when insufficient_privilege then raise notice 'Schedule the expiry job manually with a privileged DB account';end $$;

-- Seed catalog only; authenticated demo accounts and store ownership require Auth admin provisioning.
insert into public.medicines(name,generic_name,strength,form,requires_prescription) values
('Paracetamol 500','Paracetamol','500 mg','Tablet',false),('Cetirizine 10','Cetirizine','10 mg','Tablet',false),('ORS sachet','Oral rehydration salts','21 g','Sachet',false),('Antacid chewable','Calcium carbonate','500 mg','Tablet',false),('Saline nasal spray','Sodium chloride','0.65%','Spray',false),('Ibuprofen 200','Ibuprofen','200 mg','Tablet',false),('Clotrimazole cream','Clotrimazole','1%','Cream',false),('Zinc supplement','Zinc sulfate','20 mg','Tablet',false),('Vitamin C','Ascorbic acid','500 mg','Tablet',false),('Calamine lotion','Calamine','100 ml','Lotion',false),('Amoxicillin 500','Amoxicillin','500 mg','Capsule',true),('Azithromycin 500','Azithromycin','500 mg','Tablet',true),('Metformin 500','Metformin','500 mg','Tablet',true),('Amlodipine 5','Amlodipine','5 mg','Tablet',true),('Levothyroxine 50','Levothyroxine','50 mcg','Tablet',true),('Atorvastatin 10','Atorvastatin','10 mg','Tablet',true)
on conflict(name) do nothing;
