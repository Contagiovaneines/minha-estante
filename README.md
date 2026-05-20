# Minha Estante

Biblioteca digital pessoal feita em Flutter para organizar, ler e ouvir arquivos locais no Android.

O app foi pensado como uma estante offline-first: o usuário escolhe arquivos ou pastas do próprio aparelho, o app cataloga os itens, salva progresso localmente e abre cada formato no leitor ou player adequado. Não depende de login real, servidor próprio ou nuvem (totalmente privado).

## Estado do projeto

- **Plataforma principal:** Android.
- **Stack:** Flutter (3.11+), Dart, Riverpod (Gestão de Estado), GoRouter (Navegação) e Hive (Banco de Dados Local NoSQL).
- **Armazenamento:** Local no aparelho (Arquivos físicos nunca são movidos/excluídos sem consentimento).
- **Build Android:** Debug e Release operacionais.

## O que o app já tem (Funcionalidades)

### 📚 Gestão da Biblioteca Local
- **Importação Flexível:** Importe arquivos individuais ou sincronize pastas inteiras locais via seletor Android SAF.
- **Suporte Multiformato:** Catálogo centralizado para PDF, EPUB, TXT, Documentos, Mangás/HQs (CBZ, CBR, RAR) e Audiobooks (MP3, M4A, M4B, AAC, WAV, OPUS).
- **Extração Inteligente:** Puxa metadados automaticamente como capa, autor, quantidade de páginas e duração (quando o formato nativo permite).
- **Coleções e Organização:** Agrupamento automático por pastas de origem.
- **Busca e Filtros Avançados:** Pesquise por título, autor ou estante. Filtre por status: Todos, Novos, Favoritos, Lendo, Lidos e Para ler.
- **Segurança:** A remoção de um item da estante apenas limpa o catálogo, preservando o arquivo original intacto no celular (opção de apagar requer confirmação explícita).

### 📖 Leitores Especializados
- **Leitor de PDF Avançado (`pdfrx`):** Paginação fluida, marcadores, modo noturno local (inversão de cores), e salvamento exato de progresso.
- **Leitor de EPUB (`flutter_epub_viewer`):** Fonte ajustável, temas (claro/escuro/sépia), navegação por capítulos (CFI) e marcadores.
- **Leitor de HQ e Mangá (`archive`):** Leitura de CBZ nativa e descompressão de arquivos RAR/CBR em tempo real para CBZ. Suporte a zoom avançado.
- **Leitor de Documentos (TXT):** Leitura simples de arquivos de texto puro.
- **[NOVIDADE] OCR e Tradução em Tempo Real:** Escaneamento de texto em imagens (Mangás/HQs) e PDFs escaneados usando *Google ML Kit*. Traduz os balões e textos detectados para o português através da API MyMemory, com proteção antispam inteligente e contagem regressiva visual.

### 🎧 Áudio e Text-to-Speech (Ouvir Livros)
- **Audiobook Player (`just_audio`):** Toca formatos nativos de áudio com suporte a reprodução em segundo plano e controles via notificação do sistema.
- **Controle Total:** Ajuste fino da velocidade de reprodução (Pitch/Speed).
- **Texto-para-Voz (TTS):** Transforma qualquer PDF, EPUB ou arquivo TXT em audiobook usando o motor de voz nativo do Android (`flutter_tts`).
- **Leitura Sincronizada:** No modo ouvir, o app mostra a página do PDF e acompanha visualmente enquanto lê por voz. Pause o áudio e continue lendo pelo texto exatamente do mesmo ponto.

### 👤 Perfil, Estatísticas e Segurança
- **Painel de Perfil Local:** Personalize com seu nome e avatar.
- **Estatísticas Detalhadas (`fl_chart`):** Acompanhe seu ritmo de leitura com gráficos de itens lidos, status, progresso e tempo total de uso.
- **Tema Dinâmico:** Tema claro/escuro persistente baseado no sistema ou escolha manual.
- **Backup e Restauração:** Exporte toda a sua biblioteca (metadados, progresso, marcadores) em um arquivo JSON seguro e importe em outro aparelho sem perder nada.
- **Política de Privacidade:** 100% offline, os dados nunca saem do seu celular.

## Arquitetura e Rotas

A arquitetura do projeto segue uma divisão modular orientada a features:
```text
lib/
  app/ (Configurações globais, Router, Temas)
  core/ (Serviços compartilhados, banco de dados Hive, constantes)
  features/
    ├─ audio/ (Player de audiobook, Fila de reprodução)
    ├─ auth/ (Tela de Login fake/offline)
    ├─ book_detail/ (Metadados do livro, edição de capas)
    ├─ library/ (Estante principal, coleções locais)
    ├─ profile/ (Estatísticas, Backup JSON, Configurações)
    ├─ reader/ (Leitores: PDF, EPUB, HQ, TTS, Tradutor Overlay)
    └─ splash/ (Tela de carregamento)
```

## Como Rodar e Compilar

Instale as dependências e rode o app:
```bash
flutter pub get
flutter run
```

Para gerar os pacotes de distribuição local e loja:
```bash
flutter build apk --release       # Gera APK instalável manual
flutter build appbundle --release # Gera AAB para a Play Store
```

## 🚀 Ideias Futuras e Próximos Passos (Roadmap)

Aqui estão as funcionalidades mapeadas para desenvolvimento futuro:

- **Extração de Capítulos M4B:** Ler metadados embutidos (`chpl` e atomos QuickTime) para listar capítulos nativos de audiobooks, facilitando a navegação.
- **Fila Completa de Audiobooks:** Gerenciamento robusto de "Up Next" para tocar séries em sequência automaticamente.
- **Widget Nativo Android:** Um widget interativo na tela inicial do celular (usando Kotlin/Jetpack Compose) para mostrar a capa do livro atual e permitir continuar a leitura/áudio com 1 clique.
- **Editor Manual de Metadados:** Permitir trocar a capa, autor e sinopse de um livro diretamente na tela de detalhes.
- **Suporte a Nuvem (Opt-in):** Sincronizar o JSON de backup automaticamente com o Google Drive para manter o progresso em múltiplos aparelhos.
- **Melhorias em HQs Extensas:** Paginação virtual otimizada para CBZs com mais de 1000 páginas não sobrecarregarem a memória RAM.

## Licença

Este projeto é open-source offline-first licenciado sob a licença MIT. Veja [LICENSE](LICENSE).
