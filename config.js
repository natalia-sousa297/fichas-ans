// Configuração do Fichas ANS.
// Preencha os campos abaixo. Nada aqui é secreto: a chave "publishable" do Supabase
// foi feita para ficar no site. A proteção dos dados é feita pelas regras do banco.
window.FICHAS_CONFIG = {
  // Supabase > Project Settings > API
  supabaseUrl: "https://ljwutprqpcnhtzgzdmgp.supabase.co",
  supabaseKey: "sb_publishable_2Dbfk_OFZoPciGKvEBLQDg_69mByE8H",

  // Mostrado para quem criou a conta e está aguardando liberação.
  // Deixe vazio o que não quiser mostrar.
  valor: "R$ 150,00 (pagamento único)",          // ex.: "R$ 150,00 (pagamento único)"
  pixChave: "83998321210",       // sua chave PIX
  pixNome: "",          // nome que aparece no PIX
  contatoWhatsapp: "83998321210",  // só números com DDD, ex.: "11987654321"
};
