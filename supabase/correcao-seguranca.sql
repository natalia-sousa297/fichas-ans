-- Fichas ANS: correção dos avisos de segurança (rodar uma vez no SQL Editor)

-- 1) Esquema privado: a API do site não enxerga funções que ficam aqui
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- 2) Funções usadas pelas regras de acesso, agora no esquema privado
create or replace function private.is_active()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'ativo');
$$;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$;

revoke execute on function private.is_active(), private.is_admin() from public, anon;
grant execute on function private.is_active(), private.is_admin() to authenticated;

-- 3) Regras de acesso apontando para as funções privadas
drop policy if exists "perfil: ler o próprio ou admin" on public.profiles;
create policy "perfil: ler o próprio ou admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));

drop policy if exists "clientes: dono ativo" on public.clientes;
create policy "clientes: dono ativo" on public.clientes
  for all to authenticated
  using (owner = (select auth.uid()) and (select private.is_active()))
  with check (owner = (select auth.uid()) and (select private.is_active()));

drop policy if exists "produtos: dono ativo" on public.produtos;
create policy "produtos: dono ativo" on public.produtos
  for all to authenticated
  using (owner = (select auth.uid()) and (select private.is_active()))
  with check (owner = (select auth.uid()) and (select private.is_active()));

-- 4) Liberar/bloquear licença usa a função privada
create or replace function public.admin_set_status(alvo uuid, novo_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not private.is_admin() then
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
revoke execute on function public.admin_set_status(uuid, text) from public, anon;
grant execute on function public.admin_set_status(uuid, text) to authenticated;

-- 5) Apagar as versões públicas antigas
drop function if exists public.is_active();
drop function if exists public.is_admin();

-- 6) A função do cadastro só é usada pelo gatilho interno: ninguém chama pela API
revoke execute on function public.handle_new_user() from public, anon, authenticated;
