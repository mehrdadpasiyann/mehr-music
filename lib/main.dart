// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:external_path/external_path.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:on_audio_edit/on_audio_edit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_intent/receive_intent.dart' as intent;

import 'package:namida/controller/youtube_controller.dart';
import 'package:namida/controller/current_color.dart';
import 'package:namida/controller/indexer_controller.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/controller/playlist_controller.dart';
import 'package:namida/controller/queue_controller.dart';
import 'package:namida/controller/scroll_search_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/controller/video_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/functions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/core/translations/strings.dart';
import 'package:namida/core/translations/translations.dart';
import 'package:namida/packages/inner_drawer.dart';
import 'package:namida/packages/miniplayer.dart';
import 'package:namida/ui/pages/homepage.dart';
import 'package:namida/ui/pages/queues_page.dart';
import 'package:namida/ui/pages/settings_page.dart';
import 'package:namida/ui/pages/youtube_page.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/selected_tracks_preview.dart';
import 'package:namida/ui/widgets/settings/customizations.dart';
import 'package:namida/ui/widgets/settings/theme_setting.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Paint.enableDithering = true; // for smooth gradient effect.

  /// Getting Device info
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  kSdkVersion = androidInfo.version.sdkInt;

  /// Granting Storage Permission.
  /// Requesting Granular media permissions for Android 13 (API 33) doesnt work for some reason.
  /// Currently the target API is set to 32.
  if (await Permission.storage.isDenied || await Permission.storage.isPermanentlyDenied) {
    final st = await Permission.storage.request();
    if (!st.isGranted) {
      SystemNavigator.pop();
    }
  }

  // await Get.dialog(
  //   CustomBlurryDialog(
  //     title: Language.inst.STORAGE_PERMISSION,
  //     bodyText: Language.inst.STORAGE_PERMISSION_SUBTITLE,
  //     actions: [
  // CancelButton(),
  //       ElevatedButton(
  //         onPressed: () async {
  //           await Permission.storage.request();
  //           Get.close(1);
  //         },
  //         child: Text(Language.inst.GRANT_ACCESS),
  //       ),
  //     ],
  //   ),
  // );

  kAppDirectoryPath = await getExternalStorageDirectory().then((value) async => value?.path ?? await getApplicationDocumentsDirectory().then((value) => value.path));

  Future<void> createDirectories(List<String> paths) async {
    for (final p in paths) {
      await Directory(p).create(recursive: true);
    }
  }

  await createDirectories([
    kArtworksDirPath,
    kPaletteDirPath,
    kWaveformDirPath,
    kVideosCachePath,
    kVideosCacheTempPath,
    kLyricsDirPath,
    kMetadataDirPath,
    kMetadataCommentsDirPath,
  ]);

  final paths = await ExternalPath.getExternalStorageDirectories();
  kStoragePaths.assignAll(paths);
  kDirectoriesPaths = paths.map((path) => "$path/${ExternalPath.DIRECTORY_MUSIC}").toSet();
  kDirectoriesPaths.add('${paths[0]}/Download/');
  kInternalAppDirectoryPath = "${paths[0]}/Namida";

  await SettingsController.inst.prepareSettingsFile();

  Get.put(() => ScrollSearchController());
  Get.put(() => VideoController());

  await Indexer.inst.prepareTracksFile();

  PlaylistController.inst.preparePlaylistFile();
  QueueController.inst.prepareQueuesFile();

  /// updates values on startup
  Indexer.inst.updateImageSizeInStorage();
  Indexer.inst.updateWaveformSizeInStorage();
  Indexer.inst.updateVideosSizeInStorage();

  VideoController.inst.getVideoFiles();

  FlutterNativeSplash.remove();

  await PlaylistController.inst.prepareDefaultPlaylistsFile();
  await QueueController.inst.prepareLatestQueueFile();
  await Player.inst.initializePlayer();
  await Future.wait([
    PlaylistController.inst.preparePlaylistFile(),
    QueueController.inst.prepareQueuesFile(),
  ]);

  /// Recieving Initial Android Shared Intent.
  final intentfile = await intent.ReceiveIntent.getInitialIntent();
  if (intentfile != null && intentfile.extra?['real_path'] != null) {
    final playedsuccessfully = await playExternalFile(intentfile.extra?['real_path']);
    if (!playedsuccessfully) {
      Get.snackbar(Language.inst.ERROR, Language.inst.COULDNT_PLAY_FILE);
    }
  }

  /// Listening to Android Shared Intents.
  intent.ReceiveIntent.receivedIntentStream.listen((intent.Intent? intent) async {
    playExternalFile(intent?.extra?['real_path']);
  }, onError: (err) {
    Get.snackbar(Language.inst.ERROR, Language.inst.COULDNT_PLAY_FILE);
  });

  runApp(const MyApp());
}

/// returns [true] if played successfully.
Future<bool> playExternalFile(String path) async {
  final tr = await convertPathToTrack(path);
  if (tr != null) {
    Player.inst.playOrPause(0, [tr]);
    return true;
  }
  return false;
}

Future<bool> requestManageStoragePermission() async {
  if (kSdkVersion < 30) {
    return true;
  }

  if (!await Permission.manageExternalStorage.isGranted) {
    await Permission.manageExternalStorage.request();
  }

  if (!await Permission.manageExternalStorage.isGranted || await Permission.manageExternalStorage.isDenied) {
    Get.snackbar(Language.inst.STORAGE_PERMISSION_DENIED, Language.inst.STORAGE_PERMISSION_DENIED_SUBTITLE);
    return false;
  }
  return true;
}

Future<void> resetSAFPermision() async {
  if (kSdkVersion < 30) {
    return;
  }
  final didReset = await OnAudioEdit().resetComplexPermission();
  if (didReset) {
    Get.snackbar(Language.inst.PERMISSION_UPDATE, Language.inst.RESET_SAF_PERMISSION_RESET_SUCCESS);
    debugPrint('Reset SAF Successully');
  } else {
    debugPrint('Reset SAF Failure');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        Get.focusScope?.unfocus();
      },
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Namida',
        theme: AppThemes.inst.getAppTheme(CurrentColor.inst.color.value, true),
        darkTheme: AppThemes.inst.getAppTheme(CurrentColor.inst.color.value, false),
        themeMode: SettingsController.inst.themeMode.value,
        translations: MyTranslation(),
        builder: (context, widget) {
          return ScrollConfiguration(behavior: const ScrollBehaviorModified(), child: widget!);
        },
        home: MainPageWrapper(),
      ),
    );
  }
}
