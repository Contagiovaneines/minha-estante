import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_source.dart';
import '../../library/presentation/library_controller.dart';
import '../data/drive_public_api_service.dart';
import '../data/sources_repository.dart';
import '../../../core/utils/drive_link_parser.dart';

const _unset = Object();

final sourcesRepositoryProvider = Provider<SourcesRepository>(
  (ref) => LocalSourcesRepository(),
);

final driveApiServiceProvider = Provider<DrivePublicApiService>(
  (ref) => DrivePublicApiService(),
);

final sourcesControllerProvider =
    AsyncNotifierProvider<SourcesController, List<LibrarySource>>(
      SourcesController.new,
    );

final driveImportControllerProvider =
    NotifierProvider<DriveImportController, List<DriveImportTask>>(
      DriveImportController.new,
    );

enum DriveImportStatus { waiting, checking, downloading, adding, done, error }

enum DriveImportStartOutcome { started, alreadyRunning, alreadyAdded, error }

class DriveImportStartResult {
  final DriveImportStartOutcome outcome;
  final String message;
  final DriveImportTask? task;

  const DriveImportStartResult({
    required this.outcome,
    required this.message,
    this.task,
  });

  bool get isError => outcome == DriveImportStartOutcome.error;
}

class DriveImportTask {
  final String id;
  final String sourceId;
  final String userId;
  final String name;
  final String url;
  final String fileId;
  final DriveImportStatus status;
  final double? progress;
  final String statusMessage;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DriveImportTask({
    required this.id,
    required this.sourceId,
    required this.userId,
    required this.name,
    required this.url,
    required this.fileId,
    required this.status,
    this.progress,
    required this.statusMessage,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive =>
      status == DriveImportStatus.waiting ||
      status == DriveImportStatus.checking ||
      status == DriveImportStatus.downloading ||
      status == DriveImportStatus.adding;

  bool get canRetry => status == DriveImportStatus.error;

  DriveImportTask copyWith({
    String? id,
    String? sourceId,
    String? userId,
    String? name,
    String? url,
    String? fileId,
    DriveImportStatus? status,
    Object? progress = _unset,
    String? statusMessage,
    Object? errorMessage = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DriveImportTask(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      url: url ?? this.url,
      fileId: fileId ?? this.fileId,
      status: status ?? this.status,
      progress: progress == _unset ? this.progress : progress as double?,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class SourcesController extends AsyncNotifier<List<LibrarySource>> {
  final _uuid = const Uuid();

  @override
  Future<List<LibrarySource>> build() async {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return [];
    final repo = ref.read(sourcesRepositoryProvider);
    return repo.getSources(user.id);
  }

  Future<void> refresh() async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(sourcesRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => repo.getSources(user.id));
  }

  Future<String?> addSource({
    required String name,
    required String url,
    void Function(String status)? onStatus,
  }) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return 'Usuário não autenticado.';

    if (!DriveLinkParser.isValidDriveUrl(url)) {
      return 'Link inválido. Use um link do Google Drive.';
    }

    if (DriveLinkParser.isFolder(url)) {
      return 'Pastas públicas ainda não são suportadas sem API key. '
          'Adicione cada arquivo individualmente colando o link direto do arquivo.';
    }

    final fileId = DriveLinkParser.extractFileId(url);
    if (fileId == null) {
      return 'Não foi possível extrair o ID do arquivo. Verifique o link.';
    }

    final sourceId = _uuid.v4();
    final service = ref.read(driveApiServiceProvider);
    final repo = ref.read(sourcesRepositoryProvider);

    final result = await service.processPublicLink(
      userId: user.id,
      sourceId: sourceId,
      url: url,
      name: name.trim(),
      onStatus: onStatus,
    );

    if (!result.success) return result.errorMessage;

    final source = LibrarySource(
      id: sourceId,
      userId: user.id,
      name: name.trim(),
      originalUrl: url.trim(),
      driveId: fileId,
      sourceType: SourceType.file,
      itemCount: 1,
      lastSyncedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    await repo.addSource(source);
    await ref.read(libraryControllerProvider.notifier).addItem(result.item!);

    await refresh();
    return null;
  }

  Future<String?> syncSource(LibrarySource source) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return 'Usuário não autenticado.';

    final service = ref.read(driveApiServiceProvider);
    final result = await service.processPublicLink(
      userId: user.id,
      sourceId: source.id,
      url: source.originalUrl,
      name: source.name,
    );

    if (!result.success) return result.errorMessage;

    await ref.read(libraryControllerProvider.notifier).addItem(result.item!);

    final repo = ref.read(sourcesRepositoryProvider);
    await repo.updateSource(source.copyWith(lastSyncedAt: DateTime.now()));

    await refresh();
    return null;
  }

  Future<void> removeSource(String sourceId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(sourcesRepositoryProvider);
    await repo.removeSource(user.id, sourceId);
    await ref
        .read(libraryControllerProvider.notifier)
        .removeItemsBySource(sourceId);
    await refresh();
  }

  Future<void> updateSourceName({
    required LibrarySource source,
    required String name,
  }) async {
    final repo = ref.read(sourcesRepositoryProvider);
    await repo.updateSource(source.copyWith(name: name.trim()));
    await refresh();
  }
}

class DriveImportController extends Notifier<List<DriveImportTask>> {
  final _uuid = const Uuid();

  @override
  List<DriveImportTask> build() => const [];

  Future<DriveImportStartResult> startPublicFileImport({
    required String name,
    required String url,
  }) async {
    final trimmedUrl = url.trim();
    final trimmedName = name.trim();
    final user = ref.read(authControllerProvider).value;
    if (user == null) {
      return const DriveImportStartResult(
        outcome: DriveImportStartOutcome.error,
        message: 'Usuário não autenticado.',
      );
    }

    if (!DriveLinkParser.isValidDriveUrl(trimmedUrl)) {
      return const DriveImportStartResult(
        outcome: DriveImportStartOutcome.error,
        message: 'Link inválido. Use um link do Google Drive.',
      );
    }

    if (DriveLinkParser.isFolder(trimmedUrl)) {
      return const DriveImportStartResult(
        outcome: DriveImportStartOutcome.error,
        message:
            'Pastas do Drive precisam de API key para listar arquivos. '
            'Adicione arquivos individualmente.',
      );
    }

    final fileId = DriveLinkParser.extractFileId(trimmedUrl);
    if (fileId == null) {
      return const DriveImportStartResult(
        outcome: DriveImportStartOutcome.error,
        message: 'Não foi possível extrair o ID do arquivo. Verifique o link.',
      );
    }

    final existingTask = _taskByFileId(fileId);
    if (existingTask != null && existingTask.isActive) {
      return DriveImportStartResult(
        outcome: DriveImportStartOutcome.alreadyRunning,
        message:
            'Este link já está sendo importado. Acompanhe o status em Fontes.',
        task: existingTask,
      );
    }

    final repo = ref.read(sourcesRepositoryProvider);
    final sources = await repo.getSources(user.id);
    final existingSource = sources.where((source) => source.driveId == fileId);
    if (existingSource.isNotEmpty) {
      return const DriveImportStartResult(
        outcome: DriveImportStartOutcome.alreadyAdded,
        message: 'Este arquivo já foi adicionado à sua biblioteca.',
      );
    }

    final now = DateTime.now();
    final task = DriveImportTask(
      id: existingTask?.id ?? _uuid.v4(),
      sourceId: existingTask?.sourceId ?? _uuid.v4(),
      userId: user.id,
      name: trimmedName,
      url: trimmedUrl,
      fileId: fileId,
      status: DriveImportStatus.waiting,
      statusMessage: 'Aguardando importação...',
      createdAt: existingTask?.createdAt ?? now,
      updatedAt: now,
    );

    _upsertTask(task);
    unawaited(_runTask(task.id));

    return DriveImportStartResult(
      outcome: DriveImportStartOutcome.started,
      message:
          'Importação iniciada. Você pode sair desta tela; o app continuará verificando.',
      task: task,
    );
  }

  Future<void> retryTask(String taskId) async {
    final task = _taskById(taskId);
    if (task == null || !task.canRetry) return;

    final repo = ref.read(sourcesRepositoryProvider);
    final sources = await repo.getSources(task.userId);
    if (sources.any((source) => source.driveId == task.fileId)) {
      _updateTask(
        task.id,
        status: DriveImportStatus.done,
        statusMessage: 'Concluído',
      );
      return;
    }

    _updateTask(
      task.id,
      status: DriveImportStatus.waiting,
      statusMessage: 'Aguardando importação...',
      errorMessage: null,
    );
    unawaited(_runTask(task.id));
  }

  Future<void> _runTask(String taskId) async {
    try {
      await _runTaskUnsafe(taskId);
    } catch (error, stackTrace) {
      debugPrint('Erro importando link do Drive: $error\n$stackTrace');
      _updateTask(
        taskId,
        status: DriveImportStatus.error,
        statusMessage: 'Erro ao adicionar',
        errorMessage:
            'Não foi possível adicionar este arquivo. Tente novamente.',
      );
    }
  }

  Future<void> _runTaskUnsafe(String taskId) async {
    final initialTask = _taskById(taskId);
    if (initialTask == null) return;

    _updateTask(
      taskId,
      status: DriveImportStatus.checking,
      statusMessage: 'Verificando arquivo...',
    );

    final service = ref.read(driveApiServiceProvider);
    final result = await service.processPublicLink(
      userId: initialTask.userId,
      sourceId: initialTask.sourceId,
      url: initialTask.url,
      name: initialTask.name,
      onStatus: (message) => _applyServiceStatus(taskId, message),
    );

    if (!result.success) {
      _updateTask(
        taskId,
        status: DriveImportStatus.error,
        statusMessage: 'Erro ao adicionar',
        errorMessage:
            result.errorMessage ?? 'Não foi possível adicionar este arquivo.',
      );
      return;
    }

    final task = _taskById(taskId);
    if (task == null) return;

    _updateTask(
      taskId,
      status: DriveImportStatus.adding,
      statusMessage: 'Adicionando à estante...',
      progress: 1.0,
    );

    final repo = ref.read(sourcesRepositoryProvider);
    final sources = await repo.getSources(task.userId);
    final alreadyHasSource = sources.any(
      (source) => source.driveId == task.fileId,
    );

    if (!alreadyHasSource) {
      final source = LibrarySource(
        id: task.sourceId,
        userId: task.userId,
        name: task.name,
        originalUrl: task.url,
        driveId: task.fileId,
        sourceType: SourceType.file,
        itemCount: 1,
        lastSyncedAt: DateTime.now(),
        createdAt: task.createdAt,
      );

      await repo.addSource(source);
      await ref.read(libraryControllerProvider.notifier).addItem(result.item!);
    }

    await ref.read(sourcesControllerProvider.notifier).refresh();
    _updateTask(
      taskId,
      status: DriveImportStatus.done,
      statusMessage: 'Concluído',
      progress: 1.0,
    );
  }

  void _applyServiceStatus(String taskId, String message) {
    final lower = message.toLowerCase();
    final isDownload = lower.contains('baixando');
    final progress = _progressFromMessage(message);
    final status = isDownload
        ? DriveImportStatus.downloading
        : DriveImportStatus.checking;
    final statusMessage = isDownload
        ? progress == null
              ? 'Baixando arquivo...'
              : 'Baixando arquivo... ${(progress * 100).round()}%'
        : message;

    _updateTask(
      taskId,
      status: status,
      statusMessage: statusMessage,
      progress: progress,
    );
  }

  double? _progressFromMessage(String message) {
    final match = RegExp(r'(\d{1,3})%').firstMatch(message);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null) return null;
    return (value.clamp(0, 100) / 100).toDouble();
  }

  DriveImportTask? _taskById(String taskId) {
    for (final task in state) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  DriveImportTask? _taskByFileId(String fileId) {
    for (final task in state) {
      if (task.fileId == fileId) return task;
    }
    return null;
  }

  void _upsertTask(DriveImportTask task) {
    final exists = state.any((current) => current.id == task.id);
    if (!exists) {
      state = [task, ...state];
      return;
    }

    state = [
      for (final current in state)
        if (current.id == task.id) task else current,
    ];
  }

  void _updateTask(
    String taskId, {
    required DriveImportStatus status,
    required String statusMessage,
    Object? progress = _unset,
    Object? errorMessage = _unset,
  }) {
    final now = DateTime.now();
    state = [
      for (final task in state)
        if (task.id == taskId)
          task.copyWith(
            status: status,
            statusMessage: statusMessage,
            progress: progress,
            errorMessage: errorMessage,
            updatedAt: now,
          )
        else
          task,
    ];
  }
}
