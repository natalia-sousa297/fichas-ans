-- Fichas ANS: cópias automáticas (rodar depois de funcionarios.sql)
-- Todo dia o próprio banco guarda uma foto dos clientes e produtos de cada loja ativa.
-- Só guarda quando algo mudou desde a última foto. Mantém 30 dias (e sempre a última).
-- A dona vê as cópias em Conta, baixa qualquer uma e pode voltar a loja inteira para ela.

create extension if not exists pg_cron;

create table if not exists public.backups (
  id bigint generated always as identity primary key,
  loja uuid not null references public.profiles(id) on delete cascade,
  criado_em timestamptz not null default now(),
  motivo text not null default 'diaria',
  clientes integer not null default 0,
  hash text not null,
  dados jsonb not null
);
create index if not exists backups_loja_idx on public.backups(loja, criado_em desc);
alter table public.backups enable row level security;
revoke all on public.backups from anon, authenticated;
grant select on public.backups to authenticated;
drop policy if exists "backups: dona vê" on public.backups;
create policy "backups: dona vê" on public.backups for select to authenticated using (loja = (select auth.uid()));

-- foto de uma loja
create or replace function private.backup_loja(l uuid, p_motivo text)
returns bigint language plpgsql security definer set search_path = public as $$
declare d jsonb; h text; n int; novo bigint;
begin
  d := jsonb_build_object(
    'versao', 1,
    'loja', (select jsonb_build_object('loja_nome', loja_nome, 'config', config) from public.profiles where id = l),
    'clientes', coalesce((select jsonb_agg(to_jsonb(c) - 'owner' order by c.numero, c.nome) from public.clientes c where c.owner = l), '[]'::jsonb),
    'produtos', coalesce((select jsonb_agg(to_jsonb(p) - 'owner' order by p.nome) from public.produtos p where p.owner = l), '[]'::jsonb)
  );
  h := md5((d - 'loja')::text);
  if p_motivo = 'diaria' and h = (select hash from public.backups where loja = l order by criado_em desc limit 1) then
    return null; -- nada mudou
  end if;
  n := jsonb_array_length(d->'clientes');
  insert into public.backups (loja, motivo, clientes, hash, dados) values (l, p_motivo, n, h, d) returning id into novo;
  return novo;
end $$;

-- rotina diária: todas as lojas ativas, depois apaga cópias com mais de 30 dias
create or replace function private.backups_diarios()
returns void language plpgsql security definer set search_path = public as $$
declare l uuid;
begin
  for l in select id from public.profiles where loja is null and status = 'ativo' loop
    perform private.backup_loja(l, 'diaria');
  end loop;
  delete from public.backups b
   where b.criado_em < now() - interval '30 days'
     and b.id <> (select max(id) from public.backups x where x.loja = b.loja);
  delete from cron.job_run_details where end_time < now() - interval '14 days';
end $$;
revoke execute on function private.backup_loja(uuid, text), private.backups_diarios() from public, anon, authenticated;

-- 06:00 UTC = 03:00 no horário de Brasília
select cron.unschedule(jobid) from cron.job where jobname = 'fichas-backup-diario';
select cron.schedule('fichas-backup-diario', '0 6 * * *', 'select private.backups_diarios()');

-- a dona faz uma cópia na hora
create or replace function public.backup_agora()
returns bigint language plpgsql security definer set search_path = public as $$
begin
  if private.is_funcionario() or not private.is_active() then raise exception 'Apenas a dona da loja pode fazer cópias'; end if;
  if exists (select 1 from public.backups where loja = auth.uid() and motivo = 'manual' and criado_em > now() - interval '1 minute') then
    raise exception 'Uma cópia acabou de ser feita. Espere um minuto.';
  end if;
  return private.backup_loja(auth.uid(), 'manual');
end $$;

-- a dona volta a loja inteira para uma cópia (antes, guarda uma cópia de como estava)
create or replace function public.backup_restaurar(p_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare b public.backups; l uuid := auth.uid(); n int;
begin
  if private.is_funcionario() or not private.is_active() then raise exception 'Apenas a dona da loja pode restaurar cópias'; end if;
  select * into b from public.backups where id = p_id and loja = l;
  if b.id is null then raise exception 'Cópia não encontrada'; end if;

  perform private.backup_loja(l, 'antes de restaurar');
  delete from public.clientes where owner = l;
  delete from public.produtos where owner = l;

  insert into public.clientes
  select * from jsonb_populate_recordset(null::public.clientes,
    (select coalesce(jsonb_agg(e || jsonb_build_object('owner', l)), '[]'::jsonb) from jsonb_array_elements(b.dados->'clientes') e));
  get diagnostics n = row_count;
  insert into public.produtos
  select * from jsonb_populate_recordset(null::public.produtos,
    (select coalesce(jsonb_agg(e || jsonb_build_object('owner', l)), '[]'::jsonb) from jsonb_array_elements(b.dados->'produtos') e));
  return n;
end $$;

revoke execute on function public.backup_agora(), public.backup_restaurar(bigint) from public, anon;
grant execute on function public.backup_agora(), public.backup_restaurar(bigint) to authenticated;

-- primeira cópia de cada loja já agora
select private.backups_diarios();
