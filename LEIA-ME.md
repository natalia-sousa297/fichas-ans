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
- `supabase/funcionarios.sql`: funcionários e gravação por lançamento
- `supabase/backups.sql`: cópias automáticas diárias
- `supabase/logo.sql`: logo de cada loja
- `supabase/rota.sql`: ordem da rota
- `supabase/recebimento.sql`: rodar por último (guarda quem recebeu cada pagamento, para o recebimento do dia)
- Logo: cada loja escolhe a sua em **Conta > Logo da loja** (fica no banco). Loja nova começa sem logo, só com o nome. No rodapé aparece "Desenvolvido por Empresa ANS".
- `icon.svg`, `manifest.webmanifest`: ícone do aplicativo e instalação no celular

## Passos para colocar no ar (para o Claude da próxima sessão)

1. Aplicar como migração, nesta ordem: `supabase/schema.sql`, `supabase/correcao-seguranca.sql`, `supabase/funcionarios.sql`, `supabase/backups.sql`, `supabase/logo.sql`, `supabase/rota.sql` e `supabase/recebimento.sql`.
2. Rodar os avisos de segurança (get_advisors) e corrigir o que aparecer. Ficam avisos esperados de funções que pessoas logadas podem chamar: `admin_set_status`, `funcionario_convidar`, `funcionario_remover`, `backup_agora` e `backup_restaurar`. Cada uma confere dentro dela quem está chamando.
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

## Recebimento do dia

1. Na tela **Visitas** aparece o quadro **Recebido hoje** com o total e quantos pagamentos entraram. Toque em **Ver o dia**.
2. A tela mostra cada pagamento do dia com a hora, a forma (dinheiro, PIX ou cartão), quem recebeu e a observação. Em cima ficam o total e quanto entrou em cada forma.
3. Use as setas ou a data para ver outro dia.
4. A dona vê os pagamentos de todos e pode filtrar por pessoa, para conferir o dinheiro que cada funcionário trouxe. O funcionário vê só o que ele mesmo recebeu.
5. **Enviar no WhatsApp** ou **Copiar** gera o resumo do dia em texto, para o funcionário mandar para a dona no fim do dia.
6. Na hora de receber, escolha a forma de pagamento. O sistema lembra a última usada.
7. Quem recebeu é gravado pelo banco, não pelo celular, então ninguém lança no nome de outra pessoa. Pagamentos lançados antes desta opção aparecem como "Sem registro" e sem forma.

## Sem internet

Depois de abrir uma vez com internet, o sistema abre sem internet no mesmo celular, com a última cópia das fichas. Vendas, pagamentos e clientes novos ficam guardados no celular e são enviados sozinhos quando a internet volta. O aviso no topo mostra quantos lançamentos faltam enviar. Não saia da conta enquanto houver lançamentos para enviar.

## Limites do plano grátis do Supabase

- Cerca de 50 mil usuários e 500 MB de banco. Dá para muitas lojas, porque cada ficha é pequena.
- Projetos grátis são **pausados depois de 7 dias sem nenhum acesso**. Com os comerciantes usando todo dia, isso não acontece. Se acontecer, basta reativar o projeto no painel do Supabase.
- O plano grátis não tem backup automático do Supabase. Por isso o próprio banco guarda, toda madrugada (03:00), uma cópia de cada loja ativa quando algo mudou, e mantém 30 dias. A dona vê, baixa e restaura essas cópias em **Conta > Cópias de segurança**.
- Essas cópias ficam no mesmo Supabase. Para ter uma cópia fora dele, o sistema lembra a dona uma vez por semana de tocar em **Enviar para o Drive**.
