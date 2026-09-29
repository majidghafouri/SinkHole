import '../model/puzzle.dart';
import '../model/token.dart';

/// A stable identity for a puzzle, used to keep a run from repeating itself.
///
/// Two puzzles are "the same question" when the player is shown the same content
/// and offered the same set of answers. Option order is deliberately ignored,
/// because shuffling the buttons does not make a question new.
String puzzleFingerprint(Puzzle puzzle) {
  final buffer = StringBuffer(puzzle.kind.name)..write('|');

  buffer.writeAll(_bodyParts(puzzle.body), ' ');
  buffer.write('|');

  final options = puzzle.options.map(_tokenKey).toList(growable: false)..sort();
  buffer.writeAll(options, ',');

  return buffer.toString();
}

/// The visible content of a puzzle, without its answers.
///
/// Useful when the same question may legitimately reappear with a different
/// distractor draw: the player still recognises the card, so the card is what
/// should be avoided repeating.
String puzzleBodyKey(Puzzle puzzle) => puzzle.kind.name == ''
    ? ''
    : '${puzzle.kind.name}|${_bodyParts(puzzle.body).join(' ')}';

List<String> _bodyParts(PuzzleBody body) => switch (body) {
  final TextBody text => <String>['t${text.text}'],
  final TokenRowBody row => <String>[
    'r',
    for (final token in row.tokens) _tokenKey(token),
  ],
  final TokenGridBody grid => <String>[
    'g${grid.cells.length}',
    for (final token in grid.cells) _tokenKey(token),
    if (grid.revealLabel != null) _tokenKey(grid.revealLabel!),
  ],
};

String _tokenKey(Token token) {
  if (token.isGlyph) {
    return 'G${token.shape!.name}.${token.color}'
        '.${_trim(token.scale)}.${_trim(token.rotation)}';
  }
  return 'V${token.text}';
}

/// Keeps a scale readable while still distinguishing the values that matter.
String _trim(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}
