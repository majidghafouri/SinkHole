import '../core/difficulty.dart';
import 'token.dart';

/// The rotating puzzle types. The brief calls for endless variety, so every
/// entry here is a procedural template rather than hand-authored content.
enum PuzzleKind {
  /// "What comes next?" number sequence.
  sequence,

  /// Repeating shape/color pattern with a missing beat.
  pattern,

  /// Reach a target from four numbers.
  make24,

  /// 3x3 Latin-square grid with blank cells.
  gridLogic,

  /// Memorize a flash, then recall where a symbol was.
  memory,

  /// Spot the item that does not belong.
  oddOne,
}

extension PuzzleKindInfo on PuzzleKind {
  /// Short display name, used in stats.
  String get label => switch (this) {
    PuzzleKind.sequence => 'Sequence',
    PuzzleKind.pattern => 'Pattern',
    PuzzleKind.make24 => 'Make 24',
    PuzzleKind.gridLogic => 'Grid Logic',
    PuzzleKind.memory => 'Memory',
    PuzzleKind.oddOne => 'Odd One Out',
  };

  /// The instruction shown on the card. The brief caps puzzle copy at four
  /// words, so these are deliberately terse.
  String get prompt => switch (this) {
    PuzzleKind.sequence => 'NEXT NUMBER?',
    PuzzleKind.pattern => 'WHAT\'S NEXT?',
    PuzzleKind.make24 => 'MAKE 24',
    PuzzleKind.gridLogic => 'FILL THE GAP',
    PuzzleKind.memory => 'WHERE WAS IT?',
    PuzzleKind.oddOne => 'ODD ONE OUT',
  };

  /// Memory puzzles need extra time to cover the flash; sequences need less.
  double get timeFactor => switch (this) {
    PuzzleKind.sequence => 0.92,
    PuzzleKind.pattern => 0.95,
    PuzzleKind.make24 => 1.25,
    PuzzleKind.gridLogic => 1.1,
    PuzzleKind.memory => 1.45,
    PuzzleKind.oddOne => 1.0,
  };
}

/// The different things a puzzle card can render.
sealed class PuzzleBody {
  const PuzzleBody();
}

/// A line of styled text, used for the make-24 target.
class TextBody extends PuzzleBody {
  const TextBody(this.text, {this.scale = 1.0});

  final String text;
  final double scale;
}

/// A single row of tokens rendered as chips.
class TokenRowBody extends PuzzleBody {
  const TokenRowBody(this.tokens, {this.chips = true});

  final List<Token> tokens;

  /// When false the tokens are drawn bare, for tight numeric rows.
  final bool chips;
}

/// A square grid of tokens.
///
/// The size varies by depth: a 3x3 has only twelve possible Latin squares, so
/// anything that kept growing on it would start repeating. Four by four has
/// hundreds, which is why deeper runs get a bigger board.
class TokenGridBody extends PuzzleBody {
  const TokenGridBody(
    this.cells, {
    this.rows = 3,
    this.cols = 3,
    this.flashMs,
    this.revealLabel,
  });

  final List<Token> cells;
  final int rows;
  final int cols;

  /// When set, the grid is shown for this long and then hidden. The card owns
  /// the reveal/hide/ask state machine for memory puzzles.
  final int? flashMs;

  /// Shown during the flash, e.g. the symbol the player must later recall.
  final Token? revealLabel;
}

/// One fully generated puzzle.
class Puzzle {
  const Puzzle({
    required this.kind,
    required this.depth,
    required this.body,
    required this.options,
    required this.solutionIndex,
  });

  final PuzzleKind kind;
  final int depth;
  final PuzzleBody body;
  final List<Token> options;
  final int solutionIndex;

  Token get solution => options[solutionIndex];

  /// True when the card shows a timed flash before the question is answerable.
  bool get hasFlash => switch (body) {
    final TokenGridBody grid => grid.flashMs != null,
    _ => false,
  };

  /// Extra seconds granted for this puzzle type, on top of the level base.
  double get timeFactor => kind.timeFactor;

  /// Total seconds the player is given when this puzzle starts.
  double get budgetSeconds =>
      (Difficulty(depth).baseSeconds * kind.timeFactor).clamp(4.0, 16.0);

  /// The hint power-up can replay a memory flash, or delete a wrong option.
  bool get supportsFlashReplay => hasFlash;
}
