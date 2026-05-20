import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/audio_queue.dart';

final audioQueueProvider = NotifierProvider<AudioQueueNotifier, AudioQueue>(
  AudioQueueNotifier.new,
);

class AudioQueueNotifier extends Notifier<AudioQueue> {
  @override
  AudioQueue build() => const AudioQueue(itemIds: []);

  void addToQueue(String itemId) {
    state = state.withItemAdded(itemId);
  }

  void removeFromQueue(String itemId) {
    state = state.withItemRemoved(itemId);
  }

  void reorder(int oldIndex, int newIndex) {
    state = state.withReorderedItem(oldIndex, newIndex);
  }

  void jumpTo(int index) {
    state = state.jumpTo(index);
  }

  void advance() {
    state = state.advance();
  }

  void back() {
    state = state.back();
  }

  void clear() {
    state = const AudioQueue(itemIds: []);
  }

  /// Sets [itemId] as the first item and starts from there.
  void playNow(String itemId) {
    final ids = [itemId, ...state.itemIds.where((id) => id != itemId)];
    state = AudioQueue(itemIds: ids, currentIndex: 0);
  }
}
