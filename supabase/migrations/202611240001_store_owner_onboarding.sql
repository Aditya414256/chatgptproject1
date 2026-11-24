-- Applied to new Supabase project kkkolpwdxzgscpbagmfk.
-- Owners create their own first store; initial stock is demo data.
create or replace function public.setup_my_pharmacy(p_name text,p_address text,p_lat double precision,p_lng double precision,p_offers_delivery boolean default true,p_pincodes text[] default array['425405'])
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid();v_id uuid;
begin
 if v_user is null or not exists(select 1 from public.profiles where id=v_user and role='store_owner') then raise exception 'Store owner account required';end if;
 if exists(select 1 from public.stores where owner_id=v_user) then raise exception 'You already own a store';end if;
 if length(trim(coalesce(p_name,'')))<3 or length(trim(coalesce(p_address,'')))<8 then raise exception 'Enter a store name and full address';end if;
 if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Valid store location required';end if;
 if exists(select 1 from unnest(p_pincodes) p where p !~ '^\d{6}$') then raise exception 'Invalid serviceable pincode';end if;
 insert into public.stores(owner_id,name,address,lat,lng,offers_delivery,serviceable_pincodes)
 values(v_user,trim(p_name),trim(p_address),p_lat,p_lng,p_offers_delivery,p_pincodes) returning id into v_id;
 insert into public.store_inventory(store_id,medicine_id,price,stock)
 select v_id,m.id,round((20+(row_number()over(order by m.name)*7)::numeric),2),10 from public.medicines m;
 return v_id;
end $$;
revoke all on function public.setup_my_pharmacy(text,text,double precision,double precision,boolean,text[]) from public,anon;
grant execute on function public.setup_my_pharmacy(text,text,double precision,double precision,boolean,text[]) to authenticated;
alter function public.protect_profile_role() set search_path=public,pg_temp;
