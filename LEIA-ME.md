# Fichas ANS — sistema para vender a comerciantes

Site com login. Cada comerciante cria a própria conta e vê só os próprios clientes.
Contas novas ficam "aguardando liberação" até você receber o PIX e liberar na aba **Conta > Licenças**.

## Arquivos

- `index.html`: o sistema inteiro
- `config.js`: endereço e chave do Supabase, valor, chave PIX e WhatsApp de contato
- `supabase/schema.sql`: banco de dados com as regras de privacidade
- `supabase/correcao-seguranca.sql`: rodar logo depois do `schema.sql` (tira as funções internas da API)
- `logo.png`: logo oficial da ANS, que aparece no cabeçalho
- `icon.svg`, `manifest.webmanifest`: ícone do aplicativo e instalação no celular

## Passos para colocar no ar (para o Claude da próxima sessão)

1. Aplicar `supabase/schema.sql` como migração no projeto Supabase novo da usuária.
2. Rodar os avisos de segurança (get_advisors) e corrigir o que aparecer.
3. Preencher `config.js` com a URL do projeto e a chave publishable. Pedir à usuária o valor, a chave PIX, o nome do PIX e o WhatsApp de contato. Não inventar esses dados.
4. Criar um repositório no GitHub da usuária e publicar pelo GitHub Pages, a partir da raiz da branch `main`. O arquivo `.nojekyll` já está incluído.
5. Pedir à usuária para configurar no painel do Supabase, em Authentication > URL Configuration, o Site URL e o Redirect URL com o endereço do GitHub Pages.
6. A usuária cria a conta dela pelo site. Depois rode o comando abaixo, trocando pelo e-mail dela:

```sql
update public.profiles set is_admin = true, status = 'ativo', liberado_em = now() where email = 'EMAIL-DELA';
```

## Como funciona a venda

1. O comerciante abre o link e cria a conta, informando o nome da loja, o WhatsApp, o e-mail e uma senha.
2. Ele confirma o e-mail e vê a tela com o valor e a chave PIX.
3. Ele paga e manda o comprovante pelo WhatsApp.
4. Você abre **Conta > Licenças** e toca em **Liberar**. O acesso vale para sempre: é pagamento único.
5. Se precisar, dá para **Bloquear** o acesso depois.

## Limites do plano grátis do Supabase

- Cerca de 50 mil usuários e 500 MB de banco. Dá para muitas lojas, porque cada ficha é pequena.
- Projetos grátis são **pausados depois de 7 dias sem nenhum acesso**. Com os comerciantes usando todo dia, isso não acontece. Se acontecer, basta reativar o projeto no painel do Supabase.
- O plano grátis não tem backup automático. Cada loja pode baixar a própria cópia de segurança na aba Conta.
