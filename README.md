# Minha Estante

Minha Estante e uma biblioteca digital pessoal feita em Flutter para organizar,
ler e ouvir arquivos locais no celular.

O projeto e local-first: o usuario entra em um perfil local, escolhe arquivos ou
pastas do proprio aparelho, o app cataloga os itens, salva progresso, marcadores
e estatisticas no armazenamento local e abre cada formato no leitor ou player
mais adequado. Nao ha backend, login real, sincronizacao em nuvem ou servidor
proprio.

## Estado atual

- Plataforma principal: Android.
- App Flutter com rotas por `go_router`, estado com Riverpod e persistencia local
  em Hive.
- Funciona como uma estante local para livros, HQs e audiobooks.
- Possui codigo nativo Android em Kotlin para SAF, metadados, conversao de
  arquivos CBR/RAR e widget de tela inicial.
- Traducoes usam internet via MyMemory. OCR usa Google ML Kit.
- iOS e Web existem na estrutura Flutter, mas o suporte completo do app hoje e
  focado no Android.

## Funcionalidades implementadas

### Biblioteca local

- Entrada sem conta online: o botao `Entrar` cria ou reutiliza o perfil local
  `Leitor`.
- Importacao por arquivo individual na biblioteca.
- Importacao de pastas no Android via Storage Access Framework (SAF), com
  varredura recursiva dos arquivos compativeis.
- Atualizacao de pastas locais ja adicionadas.
- Agrupamento automatico em colecoes/estantes com base na pasta de origem.
- Deteccao de duplicados por titulo dentro da mesma colecao.
- Indicador de novos itens.
- Busca por titulo, autor, estante, caminho e tipo.
- Busca avancada por autor, colecao/estante e tipo.
- Filtros de status: todos, novos, favoritos, lendo, lidos e para ler.
- Tela de detalhes com capa, tipo, origem, progresso, favorito, status manual e
  acao principal para ler ou ouvir.
- Remocao segura: remove o item e o progresso do app, sem apagar o arquivo
  original do celular.
- Card "Continuar lendo" usando o ultimo item aberto.

### Formatos

| Formato | Suporte atual |
| --- | --- |
| PDF | Leitor interno, progresso por pagina, marcadores, zoom, leitura horizontal/vertical, ir para pagina, TTS e traducao de texto selecionavel. |
| EPUB | Leitor interno, progresso por CFI, marcadores, tema claro/escuro, ajuste de fonte e TTS. |
| TXT | Leitor simples com texto selecionavel e suporte a TTS. |
| CBZ/ZIP | Leitor interno de HQ/manga com extracao de imagens, ordenacao natural, zoom e traducao por OCR. |
| CBR/RAR | Conversao para CBZ em cache antes de abrir. Arquivos com senha ou acima dos limites podem falhar. |
| MP3, M4A, M4B, AAC, WAV, OPUS | Audiobooks com player interno, progresso salvo, segundo plano e fila. |
| DOC/DOCX | Catalogados, mas ainda sem leitor interno fiel. |
| MOBI, AZW, AZW3, KFX | Catalogados como ebook, mas precisam ser convertidos para EPUB para leitura interna. |
| CB7, CBT, CBA | Podem entrar no catalogo como HQ, mas o leitor/conversor completo ainda nao esta finalizado para esses formatos. |

### Leitor de PDF

- Renderizacao com `pdfrx`.
- Paginacao horizontal ou vertical.
- Zoom por gesto, botoes de zoom e duplo toque.
- Modo visual escuro para a tela de leitura.
- Marcadores por pagina.
- Dialogo para ir direto a uma pagina.
- Salvamento automatico de progresso.
- Registro de sessao de leitura para estatisticas.
- Traducao da pagina atual quando o PDF possui texto selecionavel.
- Botao para abrir o modo TTS a partir do ponto atual.

Observacao: PDFs escaneados sem texto selecionavel ainda nao entram no fluxo de
traducao/TTS do leitor de PDF.

### Leitor de EPUB

- Renderizacao com `flutter_epub_viewer`.
- Tema claro/escuro.
- Ajuste de tamanho da fonte.
- Navegacao por toque e botoes.
- Salvamento de progresso com CFI.
- Marcadores por trecho.
- Retomada aproximada por CFI ou porcentagem.

### Leitor de HQ/Manga

- Leitura de CBZ/ZIP por extracao temporaria das paginas.
- Conversao de CBR/RAR para CBZ antes da leitura.
- Limites de seguranca na conversao: ate 1 GB e ate 2000 paginas.
- Filtro contra entradas inseguras dentro de arquivos compactados.
- Ordenacao natural das paginas.
- Zoom por gesto e duplo toque.
- Barra inferior com slider de paginas.
- Opcao de traducao da pagina por OCR.
- Idiomas de origem para traducao: japones, coreano, chines simplificado,
  chines tradicional e ingles.
- As traducoes aparecem sobre os blocos detectados na imagem.
- Toque em um balao traduzido le o texto em voz alta; pressionar e segurar
  alterna entre original e traducao.
- Tratamento de limite de requisicoes da API com contagem regressiva.

### Audiobooks

- Aba propria para audiobooks.
- Importacao multipla de arquivos de audio.
- Busca por titulo ou autor.
- Lista de "Continuar ouvindo" quando ha progresso salvo.
- Player com `just_audio`.
- Reproducao em segundo plano com notificacao do sistema.
- Play/pause, avancar/voltar 15 segundos, slider de posicao e velocidades
  0.75x, 1.0x, 1.25x, 1.5x e 2.0x.
- Salvamento automatico de posicao.
- Leitura de capitulos M4B/M4A quando o arquivo possui atomos `chpl` ou trilha
  QuickTime de capitulos.
- Fila de reproducao com adicionar, remover, reordenar, limpar e tocar item da
  fila.

### Texto para voz (TTS)

- Modo "Ouvir" para PDF com texto selecionavel, EPUB e TXT.
- Extracao do texto em trechos menores.
- Idiomas configuraveis: portugues, ingles e espanhol.
- Seleciona vozes disponiveis no aparelho quando o motor TTS expoe a lista.
- Velocidades equivalentes a 0.8x, 1.0x, 1.2x e 1.4x.
- Controles de tocar, pausar, trecho anterior, proximo trecho e reiniciar.
- Para PDF, mostra uma previa da pagina relacionada ao trecho atual.
- Salva progresso especifico de TTS e tambem sincroniza com o progresso geral do
  item.

### Perfil, privacidade e estatisticas

- Perfil local com nome e avatar.
- Tema claro/escuro manual persistente.
- Tela de privacidade explicando armazenamento local, arquivos escolhidos,
  audiobooks, OCR/traducao, PIX e exclusao.
- Estatisticas com:
  - total de itens;
  - lidos;
  - lendo;
  - favoritos;
  - marcadores;
  - minutos de leitura;
  - distribuicao por tipo;
  - status da leitura;
  - itens adicionados por semana;
  - tempo de leitura por dia quando ha sessoes registradas.
- Exportacao de backup JSON.
- Importacao de backup JSON restaurando itens, progresso, progresso de TTS e
  marcadores.
- Limpeza da biblioteca local, sem apagar arquivos originais.
- Botao de contribuicao via PIX.
- Slots de publicidade simulados, sem SDK real de anuncios, com opcao gratuita
  para desativar no perfil.

### Widget Android

- Widget nativo simples para a tela inicial.
- Mostra o ultimo item aberto, subtitulo e barra de progresso.
- Toque no widget abre o app.
- O widget e atualizado quando o progresso do item e salvo.

## Como o app funciona

1. O usuario entra no perfil local.
2. Na biblioteca, adiciona uma pasta ou arquivo. Audiobooks tambem podem ser
   adicionados pela aba `Audiobooks`.
3. O app cria itens de biblioteca (`LibraryItem`) com tipo, origem, colecao,
   caminho, progresso e metadados possiveis.
4. Metadados sao extraidos quando disponiveis:
   - PDF: quantidade de paginas e miniatura da primeira pagina no Android.
   - Audio: titulo, autor, duracao e capa embutida no Android.
   - EPUB: titulo, autor, descricao e capa pelo pacote EPUB.
   - CBZ/ZIP: contagem de paginas.
5. Tudo e salvo localmente em Hive.
6. Ao abrir um item, o detalhe escolhe a rota correta:
   - PDF -> leitor PDF;
   - EPUB -> leitor EPUB;
   - TXT -> leitor de texto;
   - HQ -> leitor de HQ;
   - Audio -> player de audiobook;
   - DOC/DOCX e ebooks nao EPUB -> tela informando que ainda nao ha leitor
     interno.
7. Progresso, marcadores, sessoes, preferencias e perfil sao salvos
   localmente. A fila de audio fica em memoria durante a sessao atual.

## Estrutura do projeto

```text
lib/
  main.dart
  app/
    app.dart
    router.dart
    scaffold_with_nav.dart
    theme.dart
    theme_provider.dart
  core/
    constants/
    providers/
    services/
    storage/
    utils/
    widgets/
  features/
    audio/
    auth/
    book_detail/
    library/
    profile/
    reader/
    splash/

android/
  app/src/main/kotlin/com/minhaestante/minha_estante/
    MainActivity.kt
    MinhaEstanteWidgetProvider.kt
```

## Rotas principais

| Rota | Tela |
| --- | --- |
| `/splash` | Inicializacao |
| `/login` | Entrada local |
| `/library` | Biblioteca |
| `/audiobooks` | Lista de audiobooks |
| `/profile` | Perfil |
| `/privacy` | Privacidade |
| `/statistics` | Estatisticas |
| `/book/:id` | Detalhe do item |
| `/collection/:id` | Colecao/estante |
| `/reader/:id` | Leitor PDF |
| `/epub/:id` | Leitor EPUB |
| `/document/:id` | Leitor TXT ou aviso de formato sem leitor |
| `/hq/:id` | Leitor HQ |
| `/audio/:id` | Player de audiobook |
| `/listen/:id` | TTS |
| `/queue` | Fila de audio |

## Stack

- Flutter e Dart.
- Riverpod para estado.
- GoRouter para navegacao.
- Hive para persistencia local.
- File Picker e Android SAF para selecao de arquivos/pastas.
- Method Channels com Kotlin para funcoes Android nativas.
- `pdfrx` para PDF.
- `flutter_epub_viewer` para EPUB.
- `archive`, `rar` e Junrar nativo para arquivos compactados.
- `just_audio`, `just_audio_background` e `audio_session` para audiobooks.
- `flutter_tts` para texto para voz.
- Google ML Kit Text Recognition para OCR.
- MyMemory para traducao.
- `fl_chart` para graficos.

## Armazenamento e privacidade

- Dados do app ficam em caixas Hive locais:
  - usuarios;
  - fontes/pastas;
  - itens;
  - progresso;
  - configuracoes;
  - marcadores;
  - sessoes de leitura.
- O app nao envia biblioteca, progresso ou perfil para servidor proprio.
- Traducoes enviam o texto reconhecido para o servico MyMemory.
- O backup JSON nao copia os arquivos dos livros, HQs ou audios; ele salva os
  metadados e caminhos conhecidos pelo app.
- Ao restaurar backup em outro aparelho, os arquivos precisam existir novamente
  ou ser adicionados de novo para leitura.
- Remover item ou limpar biblioteca remove dados do app, nao os arquivos
  originais escolhidos pelo usuario.

## Como rodar

```bash
flutter pub get
flutter run
```

Para rodar os testes:

```bash
flutter test
```

Para gerar builds Android:

```bash
flutter build apk --release
flutter build appbundle --release
```

Guias auxiliares do projeto:

- `PLAY_STORE_GUIDE.md`
- `RELEASE_SETUP.md`
- `PRIVACY_POLICY.md`

## Limitacoes conhecidas

- O app e Android-first. Recursos nativos como SAF, conversao CBR/RAR, metadados
  Android, audio em segundo plano e widget dependem do Android.
- Nao existe login online nem sincronizacao automatica em nuvem.
- Backup/restauracao nao transporta os arquivos fisicos, apenas dados e caminhos.
- DOC/DOCX ainda nao possuem leitor interno.
- MOBI, AZW, AZW3 e KFX ainda precisam ser convertidos para EPUB para leitura
  interna.
- CB7, CBT e CBA ainda precisam de suporte completo no leitor/conversor.
- Traducao depende de internet e da cota do servico MyMemory.
- PDF escaneado ainda precisa de OCR dedicado para entrar no fluxo de traducao e
  TTS do leitor PDF.
- A fila de audiobooks e mantida em memoria durante a sessao atual.
- Os slots de anuncios sao placeholders internos, nao uma integracao real com
  rede de anuncios.

## Ideias futuras e melhorias

### Melhorias de curto prazo

- Persistir a fila de audiobooks entre reinicios do app.
- Melhorar o gerenciamento de cache criado por importacoes, capas extraidas,
  conversoes CBR/RAR e paginas temporarias de HQ.
- Adicionar uma tela para revisar arquivos ignorados, duplicados ou com erro na
  importacao de pastas.
- Melhorar mensagens de erro quando uma permissao Android, URI SAF ou arquivo
  externo nao puder ser acessado.
- Permitir reprocessar metadados de um item ja importado.
- Criar testes para backup, restauracao, importacao de pastas e fluxos de
  leitura.

### Novas funcionalidades

- Editor manual de metadados: titulo, autor, capa e descricao.
- Leitor ou conversor interno para DOC/DOCX.
- Conversao guiada de MOBI, AZW, AZW3 e KFX para EPUB, ou integracao de leitor
  dedicado para esses formatos.
- Suporte completo para CB7, CBT e CBA.
- Melhorias em CBR/RAR, incluindo mensagens melhores para RAR5, arquivos com
  senha e arquivos corrompidos.
- OCR para PDFs escaneados no leitor PDF.
- TTS baseado em OCR para HQs/mangas e PDFs escaneados.
- Tela de capitulos mais completa para audiobooks.
- Playlists ou series de audiobooks/livros.
- Notas pessoais por livro, pagina ou trecho.
- Tags personalizadas alem de favorito/status.
- Sincronizacao opcional via nuvem, por exemplo Google Drive, mantendo o modelo
  opt-in.

### Qualidade, loja e manutencao

- Ampliar testes automatizados de widget e integracao.
- Validar acessibilidade: contraste, tamanho de fonte, foco e leitores de tela.
- Revisar permissoes e politica de privacidade antes de publicar na Play
  Store.
- Criar screenshots e textos de loja baseados nas telas reais.
- Otimizar desempenho para HQs muito grandes.
- Melhorar suporte multiplataforma para iOS e Web, caso o projeto deixe de ser
  Android-first.

## Proxima versao planejada: limite de traducao

Hoje a traducao usa a API publica do MyMemory sem identificacao por e-mail. Por
isso, o limite pode variar conforme o IP da rede do usuario, principalmente em
Wi-Fi ou 4G compartilhado.

Segundo a documentacao oficial de limites do MyMemory, o uso gratuito anonimo e
limitado a 5.000 caracteres por dia. A API tambem permite informar um e-mail
valido no parametro `de` da requisicao, aumentando a cota gratuita para 50.000
caracteres por dia.

Uma melhoria planejada para a proxima versao e adicionar essa configuracao no
servico de traducao, respeitando privacidade e termos de uso. A ideia e usar um
e-mail valido de contato do projeto ou uma configuracao opt-in, sem enviar dados
pessoais do usuario sem aviso.

Referencia: <https://mymemory.translated.net/doc/usagelimits.php>

## Licenca

Este projeto esta licenciado sob a licenca MIT. Veja [LICENSE](LICENSE).
