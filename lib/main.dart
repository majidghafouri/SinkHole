import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/haptics.dart';
import 'audio/sound_engine.dart';
import 'data/player_profile.dart';
import 'data/save_service.dart';
import 'ui/screens/daily_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/world_palette.dart';

/// Boots the app: opens storage, renders audio, then hands control to [App].
///
/// Storage and audio are both allowed to fail. A device with a locked Hive box
/// should still be playable, and a browser that refuses to create an audio
/// context should still be silent rather than a black screen, so both are
/// non-fatal with sensible fallbacks.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  KeyValueStore store;
  try {
    store = await HiveStore.open();
  } on Object {
    store = MemoryStore();
  }
  final profile = Profile(store);

  // The UI comes up before audio is ready on purpose. Storage has to finish
  // first because the theme follows the player's deepest world, but audio does
  // not gate anything: the engine no-ops until it is ready, and waiting on it
  // here used to hold the splash screen on slower devices.
  final sound = SoundEngine();
  final haptics = Haptics(enabled: profile.hapticsEnabled);

  runApp(App(profile: profile, sound: sound, haptics: haptics));

  try {
    await sound.init();
    sound.setMuted(!profile.soundEnabled);
  } on Object {
    // Audio is a nicety; the run must still work without it.
  }
}

class App extends StatelessWidget {
  const App({
    required this.profile,
    required this.sound,
    required this.haptics,
    super.key,
  });

  final Profile profile;
  final SoundEngine sound;
  final Haptics haptics;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profile,
      builder: (context, _) {
        // The theme follows the player's deepest world, so the app feels
        // different the further the player has ever been.
        final world = Worlds.forIndex(profile.deepestWorld);
        return MaterialApp(
          title: 'Sinkhole',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(world),
          home: HomeScreen(profile: profile, sound: sound, haptics: haptics),
          routes: <String, WidgetBuilder>{
            '/daily': (_) =>
                DailyScreen(profile: profile, sound: sound, haptics: haptics),
          },
        );
      },
    );
  }
}
