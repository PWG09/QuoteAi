create table public.public_quote_tokens(
 id uuid primary key default gen_random_uuid(),
 quote_id uuid not null references public.quotes(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 token_hash bytea not null unique,
 expires_at timestamptz not null,
 revoked_at timestamptz,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now()
);
create index public_quote_tokens_quote_idx on public.public_quote_tokens(quote_id);
alter table public.public_quote_tokens enable row level security;
create policy public_quote_tokens_member on public.public_quote_tokens for all using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));

create or replace function public.get_public_quote(p_token text)
returns table(quote_id uuid,title text,status public.quote_status,customer_name text,notes text,total_cents bigint,expires_at timestamptz,items jsonb)
language sql stable security definer set search_path=public as $$
 select q.id,q.title,q.status,c.name,q.notes,q.total_cents,t.expires_at,
   coalesce((select jsonb_agg(jsonb_build_object('description',qi.description,'quantity',qi.quantity,'unitPriceCents',qi.unit_price_cents,'lineTotalCents',qi.line_total_cents) order by qi.created_at) from public.quote_items qi where qi.quote_id=q.id),'[]'::jsonb)
 from public.public_quote_tokens t
 join public.quotes q on q.id=t.quote_id and q.organization_id=t.organization_id
 join public.customers c on c.id=q.customer_id and c.organization_id=q.organization_id
 where t.token_hash=digest(p_token,'sha256') and t.revoked_at is null and t.expires_at>now();
$$;

revoke all on function public.get_public_quote(text) from public;
grant execute on function public.get_public_quote(text) to anon,authenticated;