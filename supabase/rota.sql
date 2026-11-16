-- Fichas ANS: ordem da rota (rodar depois de logo.sql)
-- Cada ficha guarda sua posição na rota da loja. A dona e os funcionários podem reorganizar.
alter table public.clientes add column if not exists ordem double precision;

create or replace function public.rota_salvar(p_itens jsonb)
returns integer language plpgsql set search_path = public as $$
declare n int;
begin
  update public.clientes c set ordem = (e->>'ordem')::double precision
    from jsonb_array_elements(p_itens) e
   where c.id = (e->>'id')::uuid;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.rota_salvar(jsonb) from public, anon;
grant execute on function public.rota_salvar(jsonb) to authenticated;
