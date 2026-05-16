import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';
import '../domain/ebook_format_support.dart';

class DocumentReaderPage extends ConsumerStatefulWidget {
  final String itemId;

  const DocumentReaderPage({super.key, required this.itemId});

  @override
  ConsumerState<DocumentReaderPage> createState() => _DocumentReaderPageState();
}

class _DocumentReaderPageState extends ConsumerState<DocumentReaderPage> {
  bool _markedOpened = false;

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryControllerProvider);

    return libraryState.when(
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Erro: $error')),
      ),
      data: (items) {
        final item = items.cast<LibraryItem?>().firstWhere(
          (entry) => entry?.id == widget.itemId,
          orElse: () => null,
        );

        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Arquivo nao encontrado.')),
          );
        }

        if (!_markedOpened) {
          _markedOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(libraryControllerProvider.notifier)
                .markItemOpened(item.id);
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            title: Text(item.title, overflow: TextOverflow.ellipsis),
          ),
          body: SafeArea(
            child: item.type == ItemType.text && item.localPath != null
                ? _TextDocumentView(path: item.localPath!)
                : _UnsupportedDocumentView(item: item),
          ),
        );
      },
    );
  }
}

class _TextDocumentView extends StatelessWidget {
  final String path;

  const _TextDocumentView({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _readText(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nao foi possivel abrir este texto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
          child: SelectableText(
            snapshot.data ?? '',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              height: 1.65,
            ),
          ),
        );
      },
    );
  }

  Future<String> _readText(String path) async {
    final bytes = await File(path).readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _UnsupportedDocumentView extends StatelessWidget {
  final LibraryItem item;

  const _UnsupportedDocumentView({required this.item});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 56, color: _color.withValues(alpha: 0.8)),
              const SizedBox(height: 14),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _message {
    switch (item.type) {
      case ItemType.hq:
        return 'Este arquivo de HQ foi adicionado a estante. O leitor interno para CBR, CBZ, CB7, CBT e CBA sera ligado em uma fase especifica.';
      case ItemType.ebook:
        if (EbookFormatSupport.canReadInternally(item)) {
          return 'Use o leitor EPUB para abrir este arquivo.';
        }
        return 'Este formato ainda não possui leitor interno nesta versão. Converta para EPUB para ler no app.';
      case ItemType.document:
        return 'Este documento foi adicionado a estante. DOC e DOCX precisam de um leitor dedicado para abrir com fidelidade.';
      case ItemType.text:
        return 'Este texto nao possui caminho local valido para leitura.';
      case ItemType.pdf:
        return 'Use o leitor de PDF para abrir este arquivo.';
      case ItemType.audio:
        return 'Use o player de audio para abrir este arquivo.';
    }
  }

  IconData get _icon {
    switch (item.type) {
      case ItemType.hq:
        return Icons.auto_stories_rounded;
      case ItemType.ebook:
        return Icons.menu_book_rounded;
      case ItemType.document:
        return Icons.description_rounded;
      case ItemType.text:
        return Icons.article_rounded;
      case ItemType.pdf:
        return Icons.picture_as_pdf_rounded;
      case ItemType.audio:
        return Icons.headphones_rounded;
    }
  }

  Color get _color {
    switch (item.type) {
      case ItemType.hq:
        return AppColors.comicAccent;
      case ItemType.ebook:
      case ItemType.pdf:
        return AppColors.primary;
      case ItemType.document:
        return AppColors.localAccent;
      case ItemType.text:
        return AppColors.textSecondary;
      case ItemType.audio:
        return AppColors.audioAccent;
    }
  }
}
