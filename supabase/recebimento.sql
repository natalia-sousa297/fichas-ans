-- Fichas ANS: recebimento do dia (rodar depois de rota.sql)
-- Cada pagamento novo guarda quem recebeu ("por" = id de quem lançou). Quem grava é o banco,
-- então ninguém lança um pagamento no nome de outra pessoa. Assim a dona confere o que cada
-- funcionário recebeu no dia, e o funcionário vê só o que ele mesmo recebeu.
-- Os outros campos do pagamento ("forma": dinheiro, pix ou cartao; "em": hora do lançamento) vêm do aparelho.
create or replace function public.pagamento_add(p_cliente uuid, p_pag jsonb)
returns public.clientes language plpgsql set search_path = public as $$
declare r public.clientes; pag jsonb := p_pag;
begin
  if auth.uid() is not null then pag := pag || jsonb_build_object('por', auth.uid()); end if;
  update public.clientes c set pagamentos = c.pagamentos || jsonb_build_array(pag)
   where c.id = p_cliente
     and not exists (select 1 from jsonb_array_elements(c.pagamentos) e where e->>'id' = pag->>'id')
  returning * into r;
  if not found then select * into r from public.clientes where id = p_cliente; end if;
  return r;
end $$;
revoke execute on function public.pagamento_add(uuid, jsonb) from public, anon;
grant execute on function public.pagamento_add(uuid, jsonb) to authenticated;
