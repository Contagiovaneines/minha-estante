# Guia de publicacao do Minha Estante na Play Store

Este documento e o roteiro pratico para transformar o app em uma primeira publicacao na Google Play. Ele separa o que ja esta no projeto, o que voce precisa criar fora do codigo e o que deve ser conferido antes de mandar para revisao.

Data de revisao: 2026-05-20.

Fontes oficiais usadas como base:

- Criar e configurar app no Play Console: https://support.google.com/googleplay/android-developer/answer/9859152
- Preparar app para revisao/App content: https://support.google.com/googleplay/android-developer/answer/9859455
- Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- Target API level: https://developer.android.com/google/play/requirements/target-sdk
- Preview assets da loja: https://support.google.com/googleplay/android-developer/answer/9866151
- User Data e Privacy Policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Testes internos/fechados: https://support.google.com/googleplay/android-developer/answer/9845334
- Requisito de teste para contas pessoais novas: https://support.google.com/googleplay/android-developer/answer/14151465

## 1. Resumo do app

Nome atual: `Minha Estante`.

Package name atual:

```text
com.minhaestante.minha_estante
```

Categoria sugerida: `Books & Reference` ou `Productivity`. A escolha final depende do posicionamento na loja.

Proposta curta:

```text
Biblioteca digital local para organizar, ler e ouvir arquivos do proprio Android.
```

Pontos fortes:

- Offline-first.
- Sem conta online obrigatoria.
- Dados salvos localmente no aparelho.
- Leitor PDF/EPUB, HQs, audiobooks e TTS no mesmo app.
- Escolha de voz instalada no Android para ouvir livros por TTS.
- Progresso sincronizado entre ler e ouvir PDF por pagina.
- Backup local e widget Android.

## 2. O que ja existe no projeto

Ja implementado:

- Biblioteca local com Hive.
- Importacao de arquivos e pastas pelo seletor Android/SAF.
- Suporte a PDF, EPUB, TXT, HQs, audiobooks e catalogo de documentos.
- Extracao automatica de metadados quando o formato permite.
- Leitor PDF, EPUB e HQ.
- TTS com idioma, voz instalada e velocidade.
- PDF visivel durante leitura por voz.
- Player de audio com background playback.
- Capitulos M4B por `chpl` e `chap`.
- Remocao de livro da estante com confirmacao.
- Tema claro/escuro com varias telas ja ajustadas.
- Widget Android.
- Configuracao Gradle para usar keystore real quando `android/key.properties` existir.
- `android/key.properties.example`.
- `PRIVACY_POLICY.md` como base de politica.

Ainda nao da para publicar sem criar itens externos:

- Conta Google Play Developer.
- Upload keystore real e senha guardada com seguranca.
- URL publica da politica de privacidade.
- Assets da loja: icone 512, feature graphic e screenshots.
- Respostas do Play Console: Data safety, Content rating, Target audience, Ads, App access e permissoes.
- Teste interno/fechado antes de producao.

## 3. Voce pode usar sem Play Store?

Sim. Para usar no seu celular antes de publicar, gere APK e instale manualmente:

```bash
flutter build apk --release
```

Arquivo:

```text
build/app/outputs/flutter-apk/app-release.apk
```

No Android, pode ser necessario liberar instalacao de apps desconhecidos para o app que abrir o APK.

Para Play Store, use AAB:

```bash
flutter build appbundle --release
```

Arquivo:

```text
build/app/outputs/bundle/release/app-release.aab
```

## 4. Checklist tecnico obrigatorio

Antes do primeiro envio:

- Confirmar se `com.minhaestante.minha_estante` e o package name definitivo. Depois que publicar, ele fica permanente.
- Gerar upload keystore real seguindo [RELEASE_SETUP.md](RELEASE_SETUP.md).
- Criar `android/key.properties` local. Nao comitar esse arquivo.
- Gerar AAB assinado com a keystore real.
- Aumentar `versionCode` a cada novo envio. Hoje:

```yaml
version: 1.0.0+1
```

O `+1` e o versionCode. Proxima build enviada poderia ser `1.0.1+2`.

- Conferir target SDK. Pelas regras atuais, a partir de 31 de agosto de 2025 novos apps e updates precisam mirar Android 15/API 35 ou superior. Se o Play Console rejeitar o AAB, atualize Flutter/Android Gradle e confirme o target final.
- Rodar validacao local:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

Arquivos sensiveis que nao podem ir para o Git:

- `android/key.properties`
- `*.jks`
- `*.keystore`
- Senhas, tokens e chaves privadas

O `.gitignore` ja bloqueia esses arquivos, mas confira antes de qualquer commit.

## 5. Assinatura e seguranca da chave

O projeto ja esta preparado para release signing quando `android/key.properties` existir.

Fluxo recomendado:

1. Gere uma upload key RSA 2048+.
2. Guarde o `.jks` em pelo menos dois lugares seguros.
3. Guarde a senha em um gerenciador de senhas.
4. Nunca envie keystore ou senha por WhatsApp, email, chat ou repositorio.
5. Ative Play App Signing no Play Console. Para app novo, normalmente o Google gera e protege a chave final de assinatura, e voce usa sua upload key para enviar novas versoes.
6. Ative verificacao em duas etapas na conta Google usada no Play Console.

Importante:

- APK/AAB gerado sem `android/key.properties` usa fallback de debug neste projeto e serve apenas para desenvolvimento/teste local.
- Para Play Store, gere AAB com keystore real.
- Se voce instalou no celular uma build debug e depois tenta instalar uma build release assinada com outra chave, talvez precise desinstalar a anterior.

## 6. Play Console, do inicio

Ordem recomendada para seu primeiro app:

1. Criar conta Google Play Developer.
2. Criar app em `Home > Create app`.
3. Definir idioma padrao, nome, app ou game, gratis ou pago e email de contato.
4. Aceitar termos e Play App Signing.
5. Preencher Store listing.
6. Preencher App content.
7. Subir AAB em Internal testing.
8. Testar pelo link do Play Console em aparelho real.
9. Se sua conta exigir, rodar Closed testing com 12 testers opt-in por 14 dias continuos antes de pedir producao.
10. Solicitar acesso/producao depois que os testes estiverem bons.

Observacao importante: contas pessoais criadas depois de 13 de novembro de 2023 podem precisar cumprir o teste fechado com pelo menos 12 testers por 14 dias antes de publicar em producao. Confira no seu Play Console, porque isso depende do tipo/data da conta.

## 7. App content: respostas iniciais

Use isto como ponto de partida. Confirme no Play Console antes de enviar.

App access:

- O app nao exige login online.
- Se o revisor consegue abrir e usar o app sem conta, marque que todas as funcionalidades estao disponiveis sem credenciais.

Ads:

- Hoje o app nao tem anuncios.

Target audience:

- Se o app nao foi feito especificamente para criancas, declare publico adulto/geral conforme o formulario permitir.
- Se incluir criancas no publico-alvo, entram regras extras da Families Policy.

Content rating:

- App de biblioteca/leitura/produtividade.
- Nao tem apostas, violencia propria, interacao social publica ou compra de conteudo pelo app.
- O conteudo importado e escolhido pelo usuario, entao nao use screenshots com livros reais protegidos por copyright.

Data safety:

- O app salva biblioteca, progresso, favoritos, estatisticas e perfil localmente.
- Nao existe backend proprio, conta online, analytics ou anuncios no fluxo atual.
- Arquivos sao escolhidos pelo usuario.
- Se voce adicionar analytics, crash reporting, login, nuvem ou traducao online obrigatoria, a declaracao muda.
- Revise tambem SDKs de terceiros, porque o Google considera dados tratados por bibliotecas.

Permissions:

- `READ_EXTERNAL_STORAGE` ate Android 12: compatibilidade para leitura de arquivos.
- `READ_MEDIA_AUDIO`: arquivos de audio locais.
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `FOREGROUND_SERVICE` e `WAKE_LOCK`: audio em segundo plano.
- `INTERNET`: hoje esta no manifest. Se nao for necessario em producao, considere remover. Se ficar, a politica deve explicar qualquer recurso online, como traducao/OCR externo se estiver ativo.

## 8. Privacidade e seguranca

O Google exige politica de privacidade em URL publica e tambem link/texto dentro do app. A politica precisa estar em pagina publica, sem login, sem bloqueio por pais e nao deve ser PDF.

Sua politica deve explicar:

- Nome do app.
- Nome do desenvolvedor ou entidade.
- Email de contato.
- Quais dados o app acessa.
- Quais dados ficam locais.
- Se algum dado e enviado para servico externo.
- Como os dados sao protegidos.
- Como o usuario apaga dados.
- Politica de retencao.

Para o Minha Estante, a declaracao provavel hoje:

- Progresso, favoritos, perfil, biblioteca e backups ficam no aparelho.
- O app nao tem conta propria.
- O app nao vende dados.
- O app nao usa anuncios.
- O app nao usa Firebase/Analytics no fluxo atual.
- O usuario escolhe arquivos/pastas explicitamente.

Pontos de atencao:

- Hive local nao esta criptografado. A politica deve dizer que os dados ficam locais e que a protecao do aparelho depende de senha/biometria do usuario.
- Nao inclua livros/capas protegidos por copyright nos assets da loja.
- Mantenha `usesCleartextTraffic=false`.
- Se mantiver recurso de traducao/OCR online, deixe claro quando texto pode ser enviado para servico externo e use HTTPS.

## 9. Store listing

Campos principais:

- App name: limite de 30 caracteres.
- Short description: limite de 80 caracteres.
- Full description: limite de 4000 caracteres.

Sugestao de nome:

```text
Minha Estante
```

Sugestao de descricao curta:

```text
Leia, organize e ouca sua biblioteca local no Android.
```

Descricao longa base:

```text
Minha Estante e uma biblioteca digital pessoal para Android.

Organize arquivos locais, leia PDFs e EPUBs, acompanhe o progresso, salve marcadores, ouca audiobooks e use leitura por voz em textos selecionaveis.

Principais recursos:
- Biblioteca local por arquivos e pastas
- Leitor PDF com progresso, marcadores e modo ouvir
- Leitor EPUB com progresso e ajustes de fonte
- Suporte a HQs em CBZ e conversao de CBR para CBZ
- Player de audiobooks com fila, velocidade e capitulos M4B
- TTS com escolha de voz instalada no aparelho
- Estatisticas de leitura
- Backup local em JSON
- Widget Android

O app foi criado para uso local. Seus arquivos e progresso ficam no aparelho. Nenhum login online e necessario.
```

Evite na descricao:

- Prometer suporte a formatos que ainda nao funcionam bem.
- Dizer "melhor", "#1", "gratis para sempre", "oficial" ou ranking.
- Repetir palavras-chave artificialmente.
- Mencionar marcas/servicos que o app nao usa.

## 10. Imagens da Play Store

App icon:

- Obrigatorio.
- PNG 32-bit com alpha.
- 512 x 512 px.
- Maximo 1024 KB.
- Nao colocar selo, preco, ranking ou texto enganoso.

Feature graphic:

- Obrigatorio.
- JPEG ou PNG 24-bit sem alpha.
- 1024 x 500 px.
- Deve mostrar a proposta do app, nao apenas repetir o icone.

Screenshots:

- Obrigatorio ter pelo menos 2.
- JPEG ou PNG 24-bit sem alpha.
- Dimensao minima: 320 px.
- Dimensao maxima: 3840 px.
- A maior dimensao nao pode ser mais que 2x a menor.
- Recomendado para app: pelo menos 4 screenshots com 1080x1920 em retrato.

Screenshots recomendadas para este app:

1. Biblioteca principal com livros locais.
2. Tela de detalhes com botoes de ler/ouvir/remover.
3. Leitor PDF com pagina aberta.
4. Modo ouvir PDF com pagina visivel e voz selecionavel.
5. Player de audiobook com capitulos/fila.
6. Perfil com estatisticas.
7. Tema escuro.
8. Widget Android na tela inicial, se estiver visualmente pronto.

Cuidados:

- Use capturas reais do app.
- Nao mostre dados pessoais reais.
- Nao use capas de livros comerciais sem permissao.
- Nao exagere em textos promocionais por cima dos prints.
- Nao mostre notificacoes, operadora ou barra de status suja.

## 11. Pagina web publica

Uma landing page completa nao e obrigatoria para todo app, mas voce precisa de uma URL publica para a politica de privacidade. Para primeiro app, recomendo criar um site simples porque ele tambem serve como suporte.

Nao use a pasta `web/` do Flutter para isso sem pensar: ela faz parte do build Flutter Web. Se criar uma pagina estatica separada, use uma pasta como:

```text
site/
  index.html
  privacy.html
  support.html
  assets/
```

Pode hospedar em:

- GitHub Pages.
- Netlify.
- Vercel.
- Cloudflare Pages.

Home precisa ter:

- Nome do app.
- Frase curta.
- 4 a 6 recursos reais.
- Screenshots reais.
- Link para politica de privacidade.
- Link para suporte.
- Link para Google Play quando publicar.

Privacy precisa ter:

- Politica em HTML, nao PDF.
- Nome do app e desenvolvedor.
- Email de contato.
- Dados acessados/coletados/compartilhados.
- Retencao e exclusao.
- Seguranca.

Support precisa ter:

- Email de suporte.
- Como remover livros da estante.
- Como apagar dados locais.
- Como reportar bug.
- Como pedir ajuda com importacao de arquivos.

## 12. Prompt para criar a pagina web

Use este prompt em outro chat/agente:

```text
Crie uma landing page estatica para o app Android "Minha Estante" em uma pasta chamada site/.

Objetivo: apresentar o app para usuarios e fornecer paginas publicas exigidas/recomendadas para Google Play.

Nao editar a pasta web/ do Flutter. Criar site separado em site/.

Estilo:
- Visual limpo, confiavel e leve.
- Responsivo mobile-first.
- Tema claro com suporte a tema escuro via CSS.
- Sem exagero de marketing.
- Boa legibilidade, contraste e foco visivel.
- Paleta neutra clara com detalhes em marrom/dourado e azul discreto.

Home:
- H1: Minha Estante
- Subtitulo: Leia, organize e ouca sua biblioteca local no Android.
- Secoes: Biblioteca local, PDF/EPUB, Audiobooks, TTS, Backup local, Privacidade.
- Area para 6 screenshots reais do app em site/assets/.
- Botao "Em breve na Google Play" como placeholder ate existir link real.
- Rodape com links para Politica de Privacidade e Suporte.

Criar tambem:
- privacy.html com politica de privacidade para app offline-first, sem conta online, sem anuncios e com dados locais.
- support.html com email de suporte, como apagar dados locais e como reportar bugs.

Requisitos tecnicos:
- HTML, CSS e JS simples.
- Sem framework pesado.
- Sem tracking, analytics ou cookies.
- Imagens com alt text.
- Layout bonito em 360px, 768px e desktop.
- Conteudo em portugues do Brasil.
```

## 13. Prompts para imagens e textos

Use imagens reais do app sempre que possivel. Para artes de apoio, nao crie telas falsas nem prometa recurso inexistente.

Feature graphic 1024 x 500:

```text
Crie uma feature graphic 1024x500 para Google Play do app "Minha Estante".
O app e uma biblioteca digital local para Android, com leitura PDF/EPUB, audiobooks, TTS e progresso.
Visual limpo, profissional, sem excesso de texto.
Mostrar uma composicao com celular exibindo uma biblioteca digital realista, livros organizados e icones sutis de leitura e audio.
Paleta neutra clara com detalhes em marrom/dourado e azul discreto.
Texto maximo: "Minha Estante".
Nao usar logos da Google Play, marcas de terceiros, capas de livros reais ou conteudo com copyright.
Formato final PNG 24-bit sem transparencia.
```

App icon:

```text
Crie um icone de app Android para "Minha Estante".
Conceito: biblioteca pessoal digital, livro/marcador e audio de forma simples.
Estilo limpo, reconhecivel em tamanho pequeno, sem texto.
Usar poucas formas, contraste alto e paleta marrom/dourado com detalhe azul discreto.
Fundo simples, sem foto, sem marca de terceiros.
Exportar PNG 512x512 com alpha e tambem versoes adaptative icon se possivel.
```

Screenshots promocionais:

```text
Criar uma imagem promocional vertical para Google Play usando uma captura real do app Minha Estante.
Adicionar legenda curta no topo: "[RECURSO]".
Manter a captura legivel, sem esconder botoes importantes.
Fundo simples, alto contraste, sem prometer recursos inexistentes.
Exportar PNG 24-bit sem transparencia em 1080x1920.
```

Legendas possiveis:

- Organize sua biblioteca local
- Leia PDF e EPUB
- Ouvir com voz do aparelho
- Audiobooks com capitulos
- Progresso e estatisticas
- Backup local

Prompt para revisar descricao da loja:

```text
Revise esta descricao da Google Play para o app "Minha Estante".
Objetivo: deixar clara, simples, sem promessa exagerada e em conformidade com boas praticas da Play Store.
Nao usar claims como "melhor", "#1", "gratis para sempre" ou chamadas agressivas.
O app e uma biblioteca local offline-first para Android, sem conta obrigatoria, com PDF/EPUB/HQ/audiobooks/TTS.
Retorne: nome, descricao curta com ate 80 caracteres e descricao longa com ate 4000 caracteres.
```

## 14. Checklist final antes de enviar

Tecnico:

- `flutter analyze` sem erros.
- `flutter test` passando.
- AAB release gerado com keystore real.
- `versionCode` maior que a ultima build enviada.
- App testado em aparelho fisico.
- Tema escuro legivel nas telas principais.
- Importacao de arquivo/pasta testada.
- PDF, EPUB, audio, TTS e backup testados.
- App sem dados pessoais reais nos exemplos.

Play Console:

- App criado.
- Play App Signing aceito.
- AAB enviado.
- Store listing preenchida.
- Iicone, feature graphic e screenshots enviados.
- Categoria escolhida.
- Email de contato informado.
- Politica de privacidade publica informada.
- Data safety preenchido.
- Content rating preenchido.
- Target audience preenchido.
- Ads declarado como nao, se continuar sem anuncios.
- App access preenchido.
- Permissoes justificadas se o console pedir.

Teste:

- Comecar por Internal testing.
- Testar pelo link do Play Console.
- Se sua conta exigir, preparar 12 testers para Closed testing por 14 dias continuos.
- Coletar feedback e corrigir bugs antes de pedir producao.

## 15. Ordem recomendada agora

1. Criar upload keystore real e `android/key.properties`.
2. Criar site publico com `privacy.html` e `support.html`.
3. Revisar permissoes Android.
4. Gerar screenshots reais do app.
5. Criar feature graphic e icone final.
6. Gerar AAB assinado.
7. Criar app no Play Console.
8. Preencher App content e Data safety com calma.
9. Publicar em Internal testing.
10. Cumprir Closed testing se o Play Console exigir.
11. Enviar para producao.

## 16. Ideias futuras

Antes da primeira publicacao, se der tempo:

- Revisar todas as telas em tema escuro.
- Remover permissao `INTERNET` se nenhum recurso online for mantido.
- Criar onboarding curto explicando biblioteca local e permissoes.
- Melhorar tela de ajuda/suporte.
- Adicionar testes de interface dos fluxos principais.

Depois da primeira publicacao:

- OCR por pagina para PDFs escaneados e HQs.
- Editor manual de metadados.
- Melhor gerenciamento de capas.
- Sync opcional com nuvem, somente com privacidade e seguranca bem definidas.
- Layout tablet.
- Localizacao completa em portugues e ingles.
