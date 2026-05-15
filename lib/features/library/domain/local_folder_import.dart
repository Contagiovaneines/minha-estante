class LocalFolderImport {
  final String name;
  final String path;
  final List<LocalFolderImportedFile> files;

  const LocalFolderImport({
    required this.name,
    required this.path,
    required this.files,
  });
}

class LocalFolderImportedFile {
  final String name;
  final String path;
  final String? relativePath;
  final int? modifiedMillis;

  const LocalFolderImportedFile({
    required this.name,
    required this.path,
    this.relativePath,
    this.modifiedMillis,
  });
}

class LocalFolderImportProgress {
  final int current;
  final int total;
  final String? fileName;
  final String phase;

  const LocalFolderImportProgress({
    required this.current,
    required this.total,
    this.fileName,
    this.phase = 'importing',
  });

  double? get percent {
    if (total <= 0) return null;
    return (current / total).clamp(0.0, 1.0);
  }

  String get percentLabel {
    final value = percent;
    if (value == null) return '0%';
    return '${(value * 100).round()}%';
  }
}
