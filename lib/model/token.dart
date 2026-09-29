/// The chunky, filled shapes used across every puzzle.
///
/// They deliberately reuse Material's filled icon glyphs so the whole set shares
/// one visual language, one corner radius, and zero asset weight.
enum ShapeKind {
  circle,
  square,
  triangle,
  star,
  diamond,
  hexagon,
  heart,
  cross,
  moon,
  arrow,
  bolt,
  drop,
}

/// A single cell of puzzle content: a number, a shape, or the blank slot.
///
/// One class rather than a hierarchy because every renderer already has to
/// handle "text or glyph", and the three tuning knobs ([scale], [rotation],
/// [color]) only matter for glyphs.
class Token {
  const Token({
    this.text,
    this.shape,
    this.color = 0,
    this.scale = 1.0,
    this.rotation = 0,
  });

  /// Literal text, e.g. `-4` or the letter of a grid cell.
  final String? text;

  /// The glyph to draw when [text] is null.
  final ShapeKind? shape;

  /// Index into the active world's accent colors.
  final int color;

  /// Multiplier applied to the glyph, used for odd-one-out size differences.
  final double scale;

  /// Radians of rotation, used for odd-one-out orientation differences.
  final double rotation;

  bool get isGlyph => shape != null;

  bool get isBlank => text == _questionMark;

  /// An unlit cell in a memory flash, as opposed to a blank the player fills.
  bool get isEmpty => text == _empty;

  static const String _questionMark = '?';
  static const String _empty = '';

  const Token.value(String this.text, {this.color = 0})
    : shape = null,
      scale = 1.0,
      rotation = 0.0;

  const Token.glyph(
    ShapeKind this.shape, {
    this.color = 0,
    this.scale = 1.0,
    this.rotation = 0.0,
  }) : text = null;

  const Token.blank()
    : text = _questionMark,
      shape = null,
      color = 0,
      scale = 1.0,
      rotation = 0.0;

  const Token.empty()
    : text = _empty,
      shape = null,
      color = 0,
      scale = 1.0,
      rotation = 0.0;

  Token copyWith({int? color, double? scale, double? rotation}) => Token(
    text: text,
    shape: shape,
    color: color ?? this.color,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
  );

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.text == text &&
      other.shape == shape &&
      other.color == color &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(text, shape, color, scale, rotation);

  @override
  String toString() => isGlyph
      ? 'Token.glyph(${shape!.name}, c$color, s$scale, r$rotation)'
      : 'Token.value($text)';
}

/// Letters used to label the cells of the memory puzzle's 3x3 recall grid.
const List<String> cellLabels = <String>[
  'A', 'B', 'C', //
  'D', 'E', 'F', //
  'G', 'H', 'I', //
];

/// Index in a 3x3 grid for a given row and column.
int gridIndex(int row, int col) => row * 3 + col;
