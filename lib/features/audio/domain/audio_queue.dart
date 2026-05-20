/// Modelo da fila de reprodução de audiobooks.
class AudioQueue {
  final List<String> itemIds;
  final int currentIndex;

  const AudioQueue({required this.itemIds, this.currentIndex = 0});

  bool get isEmpty => itemIds.isEmpty;
  bool get isNotEmpty => itemIds.isNotEmpty;
  String? get currentId => isNotEmpty && currentIndex < itemIds.length
      ? itemIds[currentIndex]
      : null;
  bool get hasNext => currentIndex < itemIds.length - 1;
  bool get hasPrevious => currentIndex > 0;

  AudioQueue copyWith({List<String>? itemIds, int? currentIndex}) {
    return AudioQueue(
      itemIds: itemIds ?? this.itemIds,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  AudioQueue withItemAdded(String id) {
    if (itemIds.contains(id)) return this;
    return copyWith(itemIds: [...itemIds, id]);
  }

  AudioQueue withItemRemoved(String id) {
    final newIds = itemIds.where((e) => e != id).toList();
    final removedIdx = itemIds.indexOf(id);
    int newIdx = currentIndex;
    if (removedIdx < currentIndex) {
      newIdx = (currentIndex - 1).clamp(0, newIds.length - 1);
    } else if (removedIdx == currentIndex) {
      newIdx = currentIndex.clamp(0, newIds.length - 1);
    }
    return AudioQueue(
      itemIds: newIds,
      currentIndex: newIds.isEmpty ? 0 : newIdx,
    );
  }

  AudioQueue withReorderedItem(int oldIndex, int newIndex) {
    final newIds = [...itemIds];
    final item = newIds.removeAt(oldIndex);
    final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    newIds.insert(insertIdx, item);
    // Update current index
    int newIdx = currentIndex;
    if (oldIndex == currentIndex) {
      newIdx = insertIdx;
    } else if (oldIndex < currentIndex && insertIdx >= currentIndex) {
      newIdx = currentIndex - 1;
    } else if (oldIndex > currentIndex && insertIdx <= currentIndex) {
      newIdx = currentIndex + 1;
    }
    return AudioQueue(
      itemIds: newIds,
      currentIndex: newIds.isEmpty ? 0 : newIdx.clamp(0, newIds.length - 1),
    );
  }

  AudioQueue advance() {
    if (!hasNext) return this;
    return copyWith(currentIndex: currentIndex + 1);
  }

  AudioQueue back() {
    if (!hasPrevious) return this;
    return copyWith(currentIndex: currentIndex - 1);
  }

  AudioQueue jumpTo(int index) {
    if (index < 0 || index >= itemIds.length) return this;
    return copyWith(currentIndex: index);
  }
}
