-- Fichas ANS: logo de cada loja (rodar depois de backups.sql)
-- A logo fica no perfil da loja como imagem pequena (data URL). Loja nova começa sem logo.
alter table public.profiles add column if not exists logo text;
alter table public.profiles drop constraint if exists profiles_logo_tamanho;
alter table public.profiles add constraint profiles_logo_tamanho check (logo is null or (length(logo) < 400000 and logo like 'data:image/%'));
grant update (logo) on public.profiles to authenticated;
