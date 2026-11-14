-- Fichas ANS — banco de dados (Supabase / Postgres)
-- Cada comerciante só enxerga os próprios dados (Row Level Security).
-- Contas novas nascem "pendente" e só funcionam depois que a administradora libera.

create extension if not exists pgcrypto;

-- ---------- perfis (uma linha por comerciante) ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  loja_nome text not null default '',
  telefone text not null default '',
  status text not null default 'pendente' check (status in ('pendente','ativo','bloqueado')),
  is_admin boolean not null default false,
  config jsonb not null default '{"sacolaoParcelas":2,"prazoDias":30}'::jsonb,
  criado_em timestamptz not null default now(),
  liberado_em timestamptz
);

-- cria o perfil automaticamente quando alguém se cadastra
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, loja_nome, telefone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'loja_nome', ''),
    coalesce(new.raw_user_meta_data->>'telefone', '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- funções auxiliares usadas pelas regras de acesso
create or replace function public.is_active()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'ativo');
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$;

alter table public.profiles enable row level security;

drop policy if exists "perfil: ler o próprio ou admin" on public.profiles;
create policy "perfil: ler o próprio ou admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "perfil: editar o próprio" on public.profiles;
create policy "perfil: editar o próprio" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- o comerciante só pode mudar nome da loja, telefone e regras; status e admin, nunca
revoke update on public.profiles from authenticated, anon;
grant update (loja_nome, telefone, config) on public.profiles to authenticated;
revoke insert, delete on public.profiles from authenticated, anon;

-- liberar / bloquear licença (só admin)
create or replace function public.admin_set_status(alvo uuid, novo_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Apenas a administração pode alterar licenças';
  end if;
  if novo_status not in ('pendente','ativo','bloqueado') then
    raise exception 'Status inválido';
  end if;
  update public.profiles
     set status = novo_status,
         liberado_em = case when novo_status = 'ativo' then coalesce(liberado_em, now()) else liberado_em end
   where id = alvo;
end $$;

revoke execute on function public.admin_set_status(uuid, text) from anon, public;
grant execute on function public.admin_set_status(uuid, text) to authenticated;

-- ---------- clientes (as fichas) ----------
create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  numero integer not null default 0,
  nome text not null,
  telefone text not null default '',
  rua text not null default '',
  numero_casa text not null default '',
  bairro text not null default '',
  cidade text not null default '',
  referencia text not null default '',
  obs text not null default '',
  proxima_visita date,
  compras jsonb not null default '[]'::jsonb,
  pagamentos jsonb not null default '[]'::jsonb,
  criado_em date not null default current_date,
  atualizado_em timestamptz not null default now()
);
create index if not exists clientes_owner_idx on public.clientes(owner);

alter table public.clientes enable row level security;

drop policy if exists "clientes: dono ativo" on public.clientes;
create policy "clientes: dono ativo" on public.clientes
  for all to authenticated
  using (owner = (select auth.uid()) and (select public.is_active()))
  with check (owner = (select auth.uid()) and (select public.is_active()));

-- ---------- produtos (catálogo de cada loja) ----------
create table if not exists public.produtos (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  nome text not null,
  cat text not null default 'sacolao' check (cat in ('sacolao','limpeza','casa')),
  preco integer not null default 0 check (preco >= 0),
  criado_em timestamptz not null default now()
);
create index if not exists produtos_owner_idx on public.produtos(owner);

alter table public.produtos enable row level security;

drop policy if exists "produtos: dono ativo" on public.produtos;
create policy "produtos: dono ativo" on public.produtos
  for all to authenticated
  using (owner = (select auth.uid()) and (select public.is_active()))
  with check (owner = (select auth.uid()) and (select public.is_active()));

-- atualiza "atualizado_em" a cada gravação
create or replace function public.touch_atualizado()
returns trigger language plpgsql set search_path = public as $$
begin new.atualizado_em = now(); return new; end $$;

drop trigger if exists clientes_touch on public.clientes;
create trigger clientes_touch before update on public.clientes
  for each row execute function public.touch_atualizado();

-- ---------- depois do seu primeiro cadastro no site, rode (troque o e-mail): ----------
-- update public.profiles set is_admin = true, status = 'ativo', liberado_em = now()
--  where email = 'SEU-EMAIL-AQUI';
