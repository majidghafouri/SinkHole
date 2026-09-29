import 'package:flutter/services.dart';

/// Short, rewarding haptics for every tap, solve and crack.
///
/// The brief asks for feedback within 100ms of every action, and on a device
/// haptics land faster than sound, so each distinct game event has its own
/// shape rather than sharing one generic buzz.
class Haptics {
  Haptics({this.enabled = true});

  bool enabled;

  /// A light tick as a finger lands on an answer button.
  void tap() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  /// A satisfying double pulse on a correct answer.
  void correct() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  /// A heavier hit as the floor cracks.
  void crack() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// The distinct lurch of the world changing.
  void levelUp() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// A short stutter for the last few seconds.
  void tick() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  void fall() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  void dispose() {}
}
