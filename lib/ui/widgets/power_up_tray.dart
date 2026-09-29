import 'package:flutter/material.dart';

import '../../engine/run_controller.dart';
import '../../model/power_up.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import 'chunky.dart';

/// The three power-up slots in the bottom tray.
///
/// Power-ups are earned, never bought, so an empty slot is a deliberate piece of
/// feedback rather than a locked slot. Long-pressing a filled one explains it,
/// which keeps the play screen free of menus while staying discoverable.
class PowerUpTray extends StatelessWidget {
  const PowerUpTray({
    required this.slots,
    required this.world,
    required this.onUse,
    required this.enabled,
    super.key,
  });

  final List<TraySlot> slots;
  final WorldPalette world;
  final ValueChanged<PowerUp> onUse;
  final bool enabled;

  static const int slotCount = 3;
  static const double size = 58;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < slotCount; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 10),
            i < slots.length
                ? _FilledSlot(
                    slot: slots[i],
                    world: world,
                    onUse: () => onUse(slots[i].powerUp),
                    enabled: enabled,
                  )
                : const _EmptySlot(),
          ],
        ],
      ),
    );
  }
}

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.slot,
    required this.world,
    required this.onUse,
    required this.enabled,
  });

  final TraySlot slot;
  final WorldPalette world;
  final VoidCallback onUse;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final power = slot.powerUp;
    return Tooltip(
      message: '${power.label}\n${power.hintText}',
      child: ChunkyButton(
        onTap: onUse,
        enabled: enabled,
        padding: EdgeInsets.zero,
        radius: 20,
        fill: world.accents[2].withValues(alpha: 0.92),
        outline: world.onCard,
        outlineWidth: 2.5,
        elevation: 3,
        semanticLabel: '${power.label}, ${slot.count} held',
        child: SizedBox.square(
          dimension: PowerUpTray.size,
          child: Stack(
            children: <Widget>[
              Center(child: Icon(power.icon, size: 26, color: world.onButton(2))),
              // The count sits in the top-right corner, clear of the glyph, and
              // only appears when more than one is held.
              if (slot.count > 1)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: world.onCard,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${slot.count}',
                      style: SinkType.rounded(
                        SinkType.caption.copyWith(
                          color: world.accentInk,
                          fontSize: 10,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An unfilled slot. It is a dashed pill with a faint plus rather than a
/// number, so it can never be mistaken for the count badge on a held power-up.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    final world = WorldScope.of(context);
    return SizedBox.square(
      dimension: PowerUpTray.size,
      child: ChunkyTile(
        radius: 20,
        dashed: true,
        outline: world.muted.withValues(alpha: 0.3),
        outlineWidth: 2,
        padding: EdgeInsets.zero,
        child: Icon(
          Icons.add_rounded,
          size: 20,
          color: world.muted.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// The small toast that slides in when a power-up is earned mid-run.
class PowerUpToast extends StatelessWidget {
  const PowerUpToast({
    required this.powerUp,
    required this.visible,
    required this.world,
    super.key,
  });

  final PowerUp powerUp;
  final bool visible;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        offset: visible ? Offset.zero : const Offset(0, -1.6),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 320),
          opacity: visible ? 1 : 0,
          child: ChunkyPill(
            fill: world.accents[2],
            outline: world.onCard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(powerUp.icon, size: 18, color: world.onButton(2)),
                const SizedBox(width: 8),
                Text(
                  '${powerUp.label.toUpperCase()} EARNED',
                  style: SinkType.rounded(
                    SinkType.label.copyWith(color: world.onButton(2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
