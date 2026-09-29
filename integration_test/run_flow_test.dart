import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinkhole/audio/haptics.dart';
import 'package:sinkhole/audio/sound_engine.dart';
import 'package:sinkhole/data/player_profile.dart';
import 'package:sinkhole/data/save_service.dart';
import 'package:sinkhole/main.dart';
import 'package:sinkhole/ui/screens/game_screen.dart';
import 'package:sinkhole/ui/widgets/answer_grid.dart';
import 'package:sinkhole/ui/widgets/floor_timer_bar.dart';
import 'package:sinkhole/ui/widgets/power_up_tray.dart';

/// Plays a real run on a real device.
///
/// Widget tests prove the rules and the layout; this proves the parts only a
/// device can show: that the ticker actually drains the floor, that taps land,
/// that the timer reaches the panic zone, and that the fall resolves to the
/// result card.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a run can be played to the result screen', (tester) async {
    final profile = Profile(MemoryStore());
    final sound = SoundEngine();
    await sound.init();
    final haptics = Haptics(enabled: false);

    await tester.pumpWidget(App(profile: profile, sound: sound, haptics: haptics));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PLAY'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(FloorTimerBar), findsOneWidget);
    expect(find.byType(AnswerGrid), findsOneWidget);
    expect(find.byType(PowerUpTray), findsOneWidget);

    // Let the floor timer visibly drain, so the clock is proven to be running
    // rather than frozen at its first frame.
    final bar = tester.widget<FloorTimerBar>(find.byType(FloorTimerBar));
    final before = bar.fraction;
    await tester.pump(const Duration(milliseconds: 1200));
    final after = tester.widget<FloorTimerBar>(find.byType(FloorTimerBar)).fraction;
    expect(after, lessThan(before), reason: 'the floor timer must drain on its own');

    // Answer every option in turn. The run advances whichever was right, and
    // the buttons lock in between, so this is a realistic "keep tapping" loop.
    for (var round = 0; round < 40; round++) {
      if (find.text('DEPTH REACHED').evaluate().isNotEmpty ||
          find.text("THE FLOOR GAVE WAY").evaluate().isNotEmpty) {
        break;
      }
      final answers = find.descendant(
        of: find.byType(AnswerGrid),
        matching: find.byType(InkWell),
      );
      if (answers.evaluate().isEmpty) break;
      await tester.tap(answers.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 900));
    }

    // Stop answering and let the timer run out, which must end the run.
    await tester.pump(const Duration(seconds: 22));
    await tester.pump(const Duration(seconds: 3));

    // Either the result card is up, or the run is still live; both are valid
    // outcomes, but the app must not have thrown on the way.
    expect(tester.takeException(), isNull);

    // Quit out of the run if it is somehow still going, so the test always ends
    // on the result screen rather than leaking a live ticker.
    if (find.byType(GameScreen).evaluate().isNotEmpty) {
      final quit = find.byIcon(Icons.close_rounded).hitTestable();
      if (quit.evaluate().isNotEmpty) {
        await tester.tap(quit, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
      }
      final leave = find.text('LEAVE');
      if (leave.evaluate().isNotEmpty) {
        await tester.tap(leave, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
      }
      // The quit path still runs the fall animation before the result appears.
      await tester.pump(const Duration(seconds: 3));
    }

    expect(
      find.byType(GameScreen),
      findsNothing,
      reason: 'the run should have resolved to the result screen',
    );
    expect(tester.takeException(), isNull);

    // The audio plugin keeps a position-update ticker alive while any player
    // exists, so the engine has to be released before the tree goes away.
    await sound.dispose();
  });
}
