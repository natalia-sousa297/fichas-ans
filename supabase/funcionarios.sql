-- Fichas ANS: funcionários e gravação segura (rodar depois de schema.sql e correcao-seguranca.sql)
-- Funcionário: vê os clientes da loja, cadastra clientes, registra pagamentos e marca visitas.
-- Não vê os totais da loja, não exclui nada e não altera vendas ou pagamentos já lançados.
-- Vender só se a dona ligar a opção "funcVendas" nas regras da loja.

-- ---------- perfis: ligação do funcionário com a loja ----------
alter table public.profiles add column if not exists loja uuid references public.profiles(id) on delete cascade;
alter table public.profiles add column if not exists nome text not null default '';
create index if not exists profiles_loja_idx on public.profiles(loja);
grant update (nome) on public.profiles to authenticated;

-- convites: e-mails que a dona cadastrou e que ainda não criaram conta
create table if not exists public.convites (
  email text primary key,
  loja uuid not null references public.profiles(id) on delete cascade,
  nome text not null default '',
  criado_em timestamptz not null default now()
);
create index if not exists convites_loja_idx on public.convites(loja);
alter table public.convites enable row level security;
revoke all on public.convites from anon, authenticated;
grant select, delete on public.convites to authenticated;
drop policy if exists "convites: dona vê" on public.convites;
create policy "convites: dona vê" on public.convites for select to authenticated using (loja = (select auth.uid()));
drop policy if exists "convites: dona apaga" on public.convites;
create policy "convites: dona apaga" on public.convites for delete to authenticated using (loja = (select auth.uid()));

-- ---------- funções internas (fora da API) ----------
create or replace function private.loja_id()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(loja, id) from public.profiles where id = auth.uid();
$$;

create or replace function private.is_funcionario()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and loja is not null);
$$;

-- ativo = a própria conta liberada e, se for funcionário, a loja também liberada
create or replace function private.is_active()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
     where p.id = auth.uid() and p.status = 'ativo'
       and (p.loja is null or exists (select 1 from public.profiles d where d.id = p.loja and d.status = 'ativo' and d.loja is null))
  );
$$;

revoke execute on function private.loja_id(), private.is_funcionario() from public, anon;
grant execute on function private.loja_id(), private.is_funcionario() to authenticated;

-- ---------- regras de acesso ----------
drop policy if exists "perfil: ler o próprio ou admin" on public.profiles;
drop policy if exists "perfil: ler o próprio, da loja ou admin" on public.profiles;
create policy "perfil: ler o próprio, da loja ou admin" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or loja = (select auth.uid())                 -- dona vê os funcionários
    or id = (select private.loja_id())            -- funcionário vê a loja
    or (select private.is_admin())
  );

drop policy if exists "clientes: dono ativo" on public.clientes;
drop policy if exists "clientes: ver" on public.clientes;
drop policy if exists "clientes: criar" on public.clientes;
drop policy if exists "clientes: alterar" on public.clientes;
drop policy if exists "clientes: excluir" on public.clientes;
create policy "clientes: ver" on public.clientes for select to authenticated
  using (owner = (select private.loja_id()) and (select private.is_active()));
create policy "clientes: criar" on public.clientes for insert to authenticated
  with check (owner = (select private.loja_id()) and (select private.is_active()));
create policy "clientes: alterar" on public.clientes for update to authenticated
  using (owner = (select private.loja_id()) and (select private.is_active()))
  with check (owner = (select private.loja_id()) and (select private.is_active()));
create policy "clientes: excluir" on public.clientes for delete to authenticated
  using (owner = (select auth.uid()) and (select private.is_active()) and not (select private.is_funcionario()));

alter table public.clientes alter column owner set default private.loja_id();

drop policy if exists "produtos: dono ativo" on public.produtos;
drop policy if exists "produtos: ver" on public.produtos;
drop policy if exists "produtos: dona altera" on public.produtos;
drop policy if exists "produtos: dona cria" on public.produtos;
drop policy if exists "produtos: dona edita" on public.produtos;
drop policy if exists "produtos: dona exclui" on public.produtos;
create policy "produtos: ver" on public.produtos for select to authenticated
  using (owner = (select private.loja_id()) and (select private.is_active()));
create policy "produtos: dona cria" on public.produtos for insert to authenticated
  with check (owner = (select auth.uid()) and (select private.is_active()) and not (select private.is_funcionario()));
create policy "produtos: dona edita" on public.produtos for update to authenticated
  using (owner = (select auth.uid()) and (select private.is_active()) and not (select private.is_funcionario()))
  with check (owner = (select auth.uid()) and (select private.is_active()) and not (select private.is_funcionario()));
create policy "produtos: dona exclui" on public.produtos for delete to authenticated
  using (owner = (select auth.uid()) and (select private.is_active()) and not (select private.is_funcionario()));

-- ---------- trava do funcionário: só acrescenta, nunca apaga nem altera lançamentos ----------
create or replace function private.clientes_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  dono uuid;
  vendas boolean;
begin
  if auth.uid() is null then return new; end if;               -- painel / SQL
  select loja into dono from public.profiles where id = auth.uid();
  if dono is null then return new; end if;                      -- dona da loja
  select coalesce((config->>'funcVendas')::boolean, false) into vendas from public.profiles where id = dono;

  if tg_op = 'INSERT' then
    if jsonb_array_length(new.pagamentos) > 0 then raise exception 'Funcionário não pode criar cliente com pagamentos'; end if;
    if not vendas and jsonb_array_length(new.compras) > 0 then raise exception 'Funcionário não pode lançar vendas'; end if;
    return new;
  end if;

  if new.owner is distinct from old.owner then raise exception 'Operação não permitida'; end if;
  if exists (select 1 from jsonb_array_elements(old.pagamentos) o where not (new.pagamentos @> jsonb_build_array(o))) then
    raise exception 'Funcionário não pode alterar ou excluir pagamentos';
  end if;
  if exists (select 1 from jsonb_array_elements(old.compras) o where not (new.compras @> jsonb_build_array(o))) then
    raise exception 'Funcionário não pode alterar ou excluir vendas';
  end if;
  if not vendas and jsonb_array_length(new.compras) > jsonb_array_length(old.compras) then
    raise exception 'Funcionário não pode lançar vendas';
  end if;
  return new;
end $$;
revoke execute on function private.clientes_guard() from public, anon, authenticated;

drop trigger if exists clientes_guard on public.clientes;
create trigger clientes_guard before insert or update on public.clientes
  for each row execute function private.clientes_guard();

-- ---------- gravação por operação (duas pessoas mexendo na mesma ficha não apagam o trabalho uma da outra) ----------
create or replace function public.cliente_salvar(p_id uuid, p_campos jsonb, p_criar boolean default false)
returns public.clientes language plpgsql set search_path = public as $$
declare r public.clientes; l uuid := private.loja_id();
begin
  update public.clientes c set
    nome           = case when p_campos ? 'nome'           then p_campos->>'nome'           else c.nome end,
    telefone       = case when p_campos ? 'telefone'       then p_campos->>'telefone'       else c.telefone end,
    rua            = case when p_campos ? 'rua'            then p_campos->>'rua'            else c.rua end,
    numero_casa    = case when p_campos ? 'numero_casa'    then p_campos->>'numero_casa'    else c.numero_casa end,
    bairro         = case when p_campos ? 'bairro'         then p_campos->>'bairro'         else c.bairro end,
    cidade         = case when p_campos ? 'cidade'         then p_campos->>'cidade'         else c.cidade end,
    referencia     = case when p_campos ? 'referencia'     then p_campos->>'referencia'     else c.referencia end,
    obs            = case when p_campos ? 'obs'            then p_campos->>'obs'            else c.obs end,
    proxima_visita = case when p_campos ? 'proxima_visita' then nullif(p_campos->>'proxima_visita', '')::date else c.proxima_visita end
  where c.id = p_id
  returning * into r;
  if found or not p_criar then return r; end if;

  insert into public.clientes (id, owner, numero, nome, telefone, rua, numero_casa, bairro, cidade, referencia, obs, proxima_visita, criado_em)
  values (
    p_id, l,
    (select coalesce(max(numero), 0) + 1 from public.clientes where owner = l),
    coalesce(p_campos->>'nome', ''), coalesce(p_campos->>'telefone', ''), coalesce(p_campos->>'rua', ''),
    coalesce(p_campos->>'numero_casa', ''), coalesce(p_campos->>'bairro', ''), coalesce(p_campos->>'cidade', ''),
    coalesce(p_campos->>'referencia', ''), coalesce(p_campos->>'obs', ''),
    nullif(p_campos->>'proxima_visita', '')::date,
    coalesce(nullif(p_campos->>'criado_em', '')::date, current_date)
  )
  returning * into r;
  return r;
end $$;

create or replace function public.pagamento_add(p_cliente uuid, p_pag jsonb)
returns public.clientes language plpgsql set search_path = public as $$
declare r public.clientes;
begin
  update public.clientes c set pagamentos = c.pagamentos || jsonb_build_array(p_pag)
   where c.id = p_cliente
     and not exists (select 1 from jsonb_array_elements(c.pagamentos) e where e->>'id' = p_pag->>'id')
  returning * into r;
  if not found then select * into r from public.clientes where id = p_cliente; end if;
  return r;
end $$;

create or replace function public.pagamento_del(p_cliente uuid, p_id text)
returns public.clientes language plpgsql set search_path = public as $$
declare r public.clientes;
begin
  update public.clientes c set pagamentos = coalesce((
      select jsonb_agg(e order by n) from jsonb_array_elements(c.pagamentos) with ordinality as t(e, n) where e->>'id' is distinct from p_id
    ), '[]'::jsonb)
   where c.id = p_cliente
  returning * into r;
  return r;
end $$;

create or replace function public.compra_salvar(p_cliente uuid, p_compra jsonb)
returns public.clientes language plpgsql set search_path = public as $$
declare r public.clientes;
begin
  update public.clientes c set compras = case
      when exists (select 1 from jsonb_array_elements(c.compras) e where e->>'id' = p_compra->>'id')
      then (select jsonb_agg(case when e->>'id' = p_compra->>'id' then p_compra else e end order by n)
              from jsonb_array_elements(c.compras) with ordinality as t(e, n))
      else c.compras || jsonb_build_array(p_compra) end
   where c.id = p_cliente
  returning * into r;
  return r;
end $$;

create or replace function public.compra_del(p_cliente uuid, p_id text)
returns public.clientes language plpgsql set search_path = public as $$
declare r public.clientes;
begin
  update public.clientes c set compras = coalesce((
      select jsonb_agg(e order by n) from jsonb_array_elements(c.compras) with ordinality as t(e, n) where e->>'id' is distinct from p_id
    ), '[]'::jsonb)
   where c.id = p_cliente
  returning * into r;
  return r;
end $$;

revoke execute on function public.cliente_salvar(uuid, jsonb, boolean), public.pagamento_add(uuid, jsonb), public.pagamento_del(uuid, text),
  public.compra_salvar(uuid, jsonb), public.compra_del(uuid, text) from public, anon;
grant execute on function public.cliente_salvar(uuid, jsonb, boolean), public.pagamento_add(uuid, jsonb), public.pagamento_del(uuid, text),
  public.compra_salvar(uuid, jsonb), public.compra_del(uuid, text) to authenticated;

-- ---------- convidar e remover funcionários (só a dona da loja) ----------
create or replace function public.funcionario_convidar(p_email text, p_nome text)
returns text language plpgsql security definer set search_path = public as $$
declare
  eu public.profiles;
  alvo public.profiles;
  em text := lower(trim(p_email));
begin
  select * into eu from public.profiles where id = auth.uid();
  if eu.id is null or eu.loja is not null or eu.status <> 'ativo' then raise exception 'Apenas a dona da loja pode cadastrar funcionários'; end if;
  if em !~ '^\S+@\S+\.\S+$' then raise exception 'E-mail inválido'; end if;
  if em = lower(eu.email) then raise exception 'Este é o seu próprio e-mail'; end if;

  select * into alvo from public.profiles where lower(email) = em;
  if alvo.id is null then
    insert into public.convites (email, loja, nome) values (em, eu.id, coalesce(trim(p_nome), ''))
      on conflict (email) do update set loja = excluded.loja, nome = excluded.nome
      where public.convites.loja = eu.id;
    if not found then raise exception 'Este e-mail já foi convidado por outra loja'; end if;
    return 'convidado';
  end if;

  if alvo.loja = eu.id then
    update public.profiles set status = 'ativo', nome = coalesce(nullif(trim(p_nome), ''), nome) where id = alvo.id;
    return 'reativado';
  end if;
  if alvo.loja is not null then raise exception 'Este e-mail já é funcionário de outra loja'; end if;
  if alvo.is_admin or alvo.status = 'ativo'
     or exists (select 1 from public.clientes where owner = alvo.id)
     or exists (select 1 from public.produtos where owner = alvo.id)
     or exists (select 1 from public.profiles where loja = alvo.id) then
    raise exception 'Este e-mail já tem uma loja própria no sistema';
  end if;
  update public.profiles
     set loja = eu.id, status = 'ativo', liberado_em = now(),
         nome = coalesce(nullif(trim(p_nome), ''), nullif(nome, ''), loja_nome)
   where id = alvo.id;
  return 'ligado';
end $$;

create or replace function public.funcionario_remover(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if private.is_funcionario() then raise exception 'Apenas a dona da loja pode remover funcionários'; end if;
  update public.profiles set status = 'bloqueado' where id = p_id and loja = auth.uid();
  if not found then raise exception 'Funcionário não encontrado'; end if;
end $$;

revoke execute on function public.funcionario_convidar(text, text), public.funcionario_remover(uuid) from public, anon;
grant execute on function public.funcionario_convidar(text, text), public.funcionario_remover(uuid) to authenticated;

-- ---------- cadastro: quem foi convidado entra direto como funcionário ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare cv public.convites;
begin
  select * into cv from public.convites where email = lower(new.email);
  if cv.email is not null then
    insert into public.profiles (id, email, loja_nome, telefone, nome, loja, status, liberado_em)
    values (new.id, new.email, '', coalesce(new.raw_user_meta_data->>'telefone', ''),
            coalesce(nullif(new.raw_user_meta_data->>'nome', ''), cv.nome), cv.loja, 'ativo', now())
    on conflict (id) do nothing;
    delete from public.convites where email = cv.email;
  else
    insert into public.profiles (id, email, loja_nome, telefone, nome)
    values (new.id, new.email,
            coalesce(new.raw_user_meta_data->>'loja_nome', ''),
            coalesce(new.raw_user_meta_data->>'telefone', ''),
            coalesce(new.raw_user_meta_data->>'nome', ''))
    on conflict (id) do nothing;
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- licenças: a administração só libera/bloqueia lojas, não funcionários
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
   where id = alvo and loja is null;
end $$;
revoke execute on function public.admin_set_status(uuid, text) from public, anon;
grant execute on function public.admin_set_status(uuid, text) to authenticated;
