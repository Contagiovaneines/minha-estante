# Minha Estante

Biblioteca digital pessoal feita em Flutter para organizar, ler e ouvir arquivos locais no Android.

O app foi pensado como uma estante offline-first: o usuario escolhe arquivos ou pastas do proprio aparelho, o app cataloga os itens, salva progresso localmente e abre cada formato no leitor ou player adequado. Nao depende de login real, servidor proprio ou Google Drive.

## Estado do projeto

- Plataforma principal: Android.
- Stack: Flutter, Dart, Riverpod, GoRouter e Hive.
- Armazenamento: local no aparelho.
- Build Android: debug e release funcionando.
- Uso fora da Play Store: possivel por APK instalado manualmente no aparelho.
- Publicacao Play Store: ainda falta preparar conta, keystore real, pagina publica de privacidade, assets da loja e revisao de checklist. Veja [PLAY_STORE_GUIDE.md](PLAY_STORE_GUIDE.md).

## O que o app ja tem

### Biblioteca local

- Importacao de arquivos individuais.
- Importacao de pastas locais pelo seletor Android SAF.
- Suporte de catalogo para PDF, EPUB, TXT, documentos, HQs e audios.
- Conversao interna de CBR/RAR para CBZ quando possivel.
- Extracao automatica de metadados: capa, autor, quantidade de paginas e duracao quando o formato permite.
- Colecoes por pasta.
- Busca por titulo, autor e estante.
- Busca avancada por autor, colecao e tipo.
- Filtros por status: todos, novos, favoritos, lendo, lidos e para ler.
- Favoritos e status manual de leitura.
- Remocao de item da estante com confirmacao. O arquivo original do celular nao e apagado.

### Leitura

- Leitor PDF com paginacao, marcador, modo noturno local, busca por pagina e progresso salvo.
- Leitor EPUB com fonte ajustavel, tema claro/escuro, progresso por CFI e marcadores.
- Leitor de HQ/CBZ.
- Conversao CBR para CBZ para abrir HQs rar.
- OCR em HQ/Manga e traducao de texto reconhecido quando o recurso for usado.
- Marcadores em PDF e EPUB.
- Registro de sessoes de leitura para estatisticas.

### Ouvir livros

- Player de audio para MP3, M4A, M4B, AAC, WAV e OPUS.
- Reproducao em segundo plano com notificacao de midia.
- Controle de velocidade.
- Fila de reproducao com reordenacao.
- Capitulos M4B por atomos `chpl` e `chap` QuickTime.
- TTS para PDF, EPUB e TXT quando existe texto selecionavel.
- Escolha de idioma, voz instalada no aparelho e velocidade do TTS.
- Para PDF, o modo ouvir mostra a pagina do PDF enquanto le por voz.
- Sincronizacao PDF leitura/ouvir: parar de ler em uma pagina e continuar ouvindo dali; parar de ouvir e voltar a ler na mesma pagina.

### Perfil, estatisticas e backup

- Perfil local com nome e foto.
- Tema claro/escuro persistente.
- Estatisticas por tipo, status, progresso e tempo de uso.
- Exportacao de backup JSON.
- Importacao de backup JSON sem duplicar itens.
- Politica de privacidade dentro do app.
- Widget Android na tela inicial com ultimo item/progresso.

## Arquitetura resumida

```text
lib/
  app/
    app.dart
    router.dart
    scaffold_with_nav.dart
    theme.dart
    theme_provider.dart
  core/
    constants/
    services/
    storage/
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

## Pacotes principais

| Pacote | Uso |
|---|---|
| `flutter_riverpod` | Estado da aplicacao |
| `go_router` | Rotas |
| `hive_flutter` | Banco local |
| `pdfrx` | PDF |
| `flutter_epub_viewer` | EPUB |
| `just_audio` e `just_audio_background` | Audio e background |
| `flutter_tts` | Texto para voz |
| `file_picker` | Escolha de arquivos |
| `archive` e `rar` | HQs, CBZ e conversao |
| `fl_chart` | Graficos de estatisticas |

## Como rodar

```bash
flutter pub get
flutter run
```

## Como testar

```bash
flutter analyze
flutter test
flutter build apk --debug
```

## Gerar APK local

```bash
flutter build apk --release
```

Arquivo gerado:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Para publicar na Play Store, use App Bundle:

```bash
flutter build appbundle --release
```

Arquivo gerado:

```text
build/app/outputs/bundle/release/app-release.aab
```

Leia tambem:

- [RELEASE_SETUP.md](RELEASE_SETUP.md): assinatura Android.
- [PLAY_STORE_GUIDE.md](PLAY_STORE_GUIDE.md): checklist completo para publicar seu primeiro app.
- [PRIVACY_POLICY.md](PRIVACY_POLICY.md): politica de privacidade base.

## O que falta para publicar

- Criar a conta Google Play Developer.
- Confirmar que `com.minhaestante.minha_estante` sera o package name definitivo.
- Criar uma upload keystore real e o arquivo local `android/key.properties`.
- Gerar o AAB assinado com `flutter build appbundle --release`.
- Criar uma URL publica para a politica de privacidade.
- Criar icone final, feature graphic e screenshots reais do app.
- Preencher Data safety, Content rating, Target audience, Ads e App access no Play Console.
- Rodar teste interno/fechado antes da producao.

## Ideias futuras

- OCR por pagina para PDFs escaneados e HQs.
- Editor manual de metadados do livro.
- Melhor pagina de detalhes com historico de leitura.
- Exportar/importar biblioteca em formato mais amigavel.
- Criar landing page publica com politica de privacidade e suporte.
- Testes de interface para fluxos principais.
- Pipeline de build assinado em CI.
- Revisao completa de acessibilidade.
- Localizacao completa em portugues e ingles.
- Melhorar performance em bibliotecas muito grandes.

## Licenca

Este projeto esta licenciado sob a licenca MIT. Veja [LICENSE](LICENSE).
