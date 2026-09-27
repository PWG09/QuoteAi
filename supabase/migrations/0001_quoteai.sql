create extension if not exists pgcrypto;

create type public.organization_role as enum ('owner','admin','manager','member','viewer');
create type public.membership_status as enum ('active','invited','suspended');
create type public.quote_status as enum ('draft','sent','accepted','declined','expired','cancelled');

create table public.organizations(
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 2 and 160),
 slug text not null unique check(slug ~ '^[a-z0-9-]+$'), created_at timestamptz not null default now(), created_by uuid not null references auth.users(id)
);
create table public.organization_members(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, role public.organization_role not null default 'member',
 status public.membership_status not null default 'active', created_at timestamptz not null default now(), unique(organization_id,user_id)
);
create table public.app_permissions(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, app text not null default 'quoteai',
 permission text not null, created_at timestamptz not null default now(), unique(organization_id,user_id,app,permission)
);
create table public.customers(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(name) between 2 and 120), email text, phone text, notes text,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.services(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(name) between 2 and 160), description text, price_cents bigint not null check(price_cents>=0),
 active boolean not null default true, created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table public.quotes(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 customer_id uuid not null references public.customers(id), title text not null, notes text,
 status public.quote_status not null default 'draft', subtotal_cents bigint not null default 0 check(subtotal_cents>=0),
 tax_cents bigint not null default 0 check(tax_cents>=0), total_cents bigint not null default 0 check(total_cents>=0),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.quote_items(
 id uuid primary key default gen_random_uuid(), quote_id uuid not null references public.quotes(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade, service_id uuid references public.services(id) on delete set null,
 description text not null, quantity integer not null check(quantity>0 and quantity<=10000), unit_price_cents bigint not null check(unit_price_cents>=0),
 line_total_cents bigint not null check(line_total_cents>=0), created_at timestamptz not null default now()
);
create table public.quote_versions(
 id uuid primary key default gen_random_uuid(), quote_id uuid not null references public.quotes(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade, version integer not null check(version>0),
 snapshot jsonb not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), unique(quote_id,version)
);
create table public.ai_generations(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id), provider text not null, input text not null check(length(input)<=6000), output jsonb not null, created_at timestamptz not null default now()
);
create table public.audit_logs(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid references auth.users(id), action text not null, resource_type text, resource_id uuid, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create index organization_members_user_idx on public.organization_members(user_id);
create index customers_org_idx on public.customers(organization_id,created_at desc);
create index services_org_idx on public.services(organization_id,active);
create index quotes_org_idx on public.quotes(organization_id,created_at desc);
create index quote_items_quote_idx on public.quote_items(quote_id);
create index audit_logs_org_idx on public.audit_logs(organization_id,created_at desc);

create or replace function public.is_org_member(p_org uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active');
$$;

create or replace function public.has_org_role(p_org uuid,p_roles public.organization_role[]) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active' and m.role=any(p_roles));
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
 declare org_id uuid; display_name text; base_slug text;
 begin
  display_name=coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1));
  base_slug=lower(regexp_replace(display_name,'[^a-zA-Z0-9]+','-','g'));
  insert into public.organizations(name,slug,created_by) values(left(display_name||' Workspace',160),left(base_slug||'-'||substr(new.id::text,1,8),80),new.id) returning id into org_id;
  insert into public.organization_members(organization_id,user_id,role) values(org_id,new.id,'owner');
  insert into public.app_permissions(organization_id,user_id,app,permission) values
   (org_id,new.id,'quoteai','read'),(org_id,new.id,'quoteai','write'),(org_id,new.id,'quoteai','manage');
  return new;
 end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.validate_quote_tenant() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.customers c where c.id=new.customer_id and c.organization_id=new.organization_id) then raise exception 'customer belongs to another organization'; end if;
 return new;
end; $$;
create trigger quote_tenant_check before insert or update on public.quotes for each row execute function public.validate_quote_tenant();

create or replace function public.validate_quote_item_tenant() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.quotes q where q.id=new.quote_id and q.organization_id=new.organization_id) then raise exception 'quote belongs to another organization'; end if;
 if new.service_id is not null and not exists(select 1 from public.services s where s.id=new.service_id and s.organization_id=new.organization_id) then raise exception 'service belongs to another organization'; end if;
 if new.line_total_cents <> new.quantity*new.unit_price_cents then raise exception 'invalid line total'; end if;
 return new;
end; $$;
create trigger quote_item_tenant_check before insert or update on public.quote_items for each row execute function public.validate_quote_item_tenant();

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.app_permissions enable row level security;
alter table public.customers enable row level security;
alter table public.services enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
alter table public.quote_versions enable row level security;
alter table public.ai_generations enable row level security;
alter table public.audit_logs enable row level security;

create policy organizations_select on public.organizations for select using(public.is_org_member(id));
create policy organizations_update on public.organizations for update using(public.has_org_role(id,array['owner','admin']::public.organization_role[])) with check(public.has_org_role(id,array['owner','admin']::public.organization_role[]));
create policy members_select on public.organization_members for select using(public.is_org_member(organization_id));
create policy members_manage on public.organization_members for all using(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[])) with check(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[]));
create policy permissions_select on public.app_permissions for select using(public.is_org_member(organization_id));
create policy permissions_manage on public.app_permissions for all using(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[])) with check(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[]));
create policy customers_all on public.customers for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
create policy services_all on public.services for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
create policy quotes_all on public.quotes for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
create policy quote_items_all on public.quote_items for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
create policy quote_versions_all on public.quote_versions for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
create policy ai_generations_all on public.ai_generations for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
create policy audit_logs_select on public.audit_logs for select using(public.has_org_role(organization_id,array['owner','admin','manager']::public.organization_role[]));
create policy audit_logs_insert on public.audit_logs for insert with check(public.is_org_member(organization_id));