import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/storage/local_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.minhaestante.minha_estante.audiobooks',
    androidNotificationChannelName: 'Audiobooks',
    androidNotificationChannelDescription:
        'Reproducao de audiobooks em segundo plano',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  final appDocDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocDir.path);

  await LocalStorageService.init();

  runApp(const ProviderScope(child: MinhaEstanteApp()));
}
