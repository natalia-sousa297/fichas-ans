# Fichas ANS — sistema para vender a comerciantes

Site com login. Cada comerciante cria a própria conta e vê só os próprios clientes.
Contas novas ficam "aguardando liberação" até você receber o PIX e liberar na aba **Conta > Licenças**.

## Arquivos

- `index.html`: o sistema inteiro
- `sw.js`: guarda o sistema no celular para abrir sem internet
- `vendor/`: bibliotecas do Supabase e do PDF, guardadas junto com o site para funcionar sem internet
- `config.js`: endereço e chave do Supabase, valor, chave PIX e WhatsApp de contato
- `supabase/schema.sql`: banco de dados com as regras de privacidade
- `supabase/correcao-seguranca.sql`: rodar logo depois do `schema.sql` (tira as funções internas da API)
- `supabase/funcionarios.sql`: rodar por último (funcionários e gravação por lançamento)
- `logo.png`: logo oficial da ANS, que aparece no cabeçalho
- `icon.svg`, `manifest.webmanifest`: ícone do aplicativo e instalação no celular

## Passos para colocar no ar (para o Claude da próxima sessão)

1. Aplicar como migração, nesta ordem: `supabase/schema.sql`, `supabase/correcao-seguranca.sql` e `supabase/funcionarios.sql`.
2. Rodar os avisos de segurança (get_advisors) e corrigir o que aparecer. Ficam três avisos esperados de funções que pessoas logadas podem chamar: `admin_set_status`, `funcionario_convidar` e `funcionario_remover`. Cada uma confere dentro dela quem está chamando.
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

## Funcionários

1. A dona abre **Conta > Funcionários** e cadastra o nome e o e-mail do funcionário.
2. O funcionário abre o link, toca em **Criar conta**, escolhe **Sou funcionário** e usa o mesmo e-mail.
3. Ele vê as visitas e as fichas, cadastra clientes, recebe pagamentos e marca visitas. Não vê os totais da loja, não baixa a cópia de segurança e não exclui nem corrige lançamentos. Lançar vendas só se a dona marcar **Funcionários podem lançar vendas**.
4. Essas travas valem no banco de dados, não só na tela.
5. Para tirar o acesso, toque em **Remover**. Para devolver, **Devolver acesso**.
6. Funcionário não paga licença. Se a loja for bloqueada, os funcionários dela também perdem o acesso.

## Sem internet

Depois de abrir uma vez com internet, o sistema abre sem internet no mesmo celular, com a última cópia das fichas. Vendas, pagamentos e clientes novos ficam guardados no celular e são enviados sozinhos quando a internet volta. O aviso no topo mostra quantos lançamentos faltam enviar. Não saia da conta enquanto houver lançamentos para enviar.

## Limites do plano grátis do Supabase

- Cerca de 50 mil usuários e 500 MB de banco. Dá para muitas lojas, porque cada ficha é pequena.
- Projetos grátis são **pausados depois de 7 dias sem nenhum acesso**. Com os comerciantes usando todo dia, isso não acontece. Se acontecer, basta reativar o projeto no painel do Supabase.
- O plano grátis não tem backup automático. Cada loja pode baixar a própria cópia de segurança na aba Conta.
