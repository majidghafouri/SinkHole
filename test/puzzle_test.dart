import 'package:flutter_test/flutter_test.dart';
import 'package:sinkhole/core/difficulty.dart';
import 'package:sinkhole/core/game_random.dart';
import 'package:sinkhole/model/puzzle.dart';
import 'package:sinkhole/model/token.dart';
import 'package:sinkhole/puzzle/grid_generator.dart';
import 'package:sinkhole/puzzle/make24_generator.dart';
import 'package:sinkhole/puzzle/memory_generator.dart';
import 'package:sinkhole/puzzle/odd_one_generator.dart';
import 'package:sinkhole/puzzle/pattern_generator.dart';
import 'package:sinkhole/puzzle/puzzle_factory.dart';
import 'package:sinkhole/puzzle/sequence_generator.dart';
import 'package:sinkhole/puzzle/sequence_rules.dart';
import 'package:sinkhole/puzzle/target_solver.dart';

/// Reads the visible numbers out of a sequence puzzle.
List<int> _sequenceTerms(Puzzle p) {
  final body = p.body as TokenRowBody;
  return body.tokens.map((t) => int.parse(t.text!)).toList();
}

void main() {
  group('puzzle invariants', () {
    // Every generator must satisfy these, at every depth, on every seed.
    for (var depth = 1; depth <= 60; depth++) {
      test('depth $depth produces well-formed puzzles', () {
        final factory = PuzzleFactory();
        for (var seed = 0; seed < 12; seed++) {
          final rng = GameRandom(seed * 7919 + depth);
          final puzzle = factory.build(rng, depth, boss: seed.isEven);
          final tag = 'seed=$seed depth=$depth kind=${puzzle.kind}';

          expect(
            puzzle.options.length,
            inInclusiveRange(2, 4),
            reason: '$tag has ${puzzle.options.length} options',
          );
          expect(
            puzzle.solutionIndex,
            inInclusiveRange(0, puzzle.options.length - 1),
            reason: '$tag has an out-of-range solution',
          );
          expect(puzzle.budgetSeconds, greaterThan(0), reason: tag);

          if (puzzle.kind == PuzzleKind.oddOne) {
            // The odd-one-out deliberately shows three identical options, so
            // distinctness is checked by kind rather than universally.
            expect(
              puzzle.options.where((t) => t != puzzle.solution).toSet(),
              hasLength(1),
              reason: '$tag must have exactly one odd option',
            );
          } else {
            // Otherwise every option must be visually distinct, since two
            // interchangeable buttons would make the puzzle unfair.
            expect(
              puzzle.options.toSet(),
              hasLength(puzzle.options.length),
              reason: '$tag has a duplicate option',
            );
          }
        }
      });
    }

    test('option counts are stable per puzzle type', () {
      final factory = PuzzleFactory();
      final counts = <PuzzleKind, Set<int>>{};
      for (var seed = 0; seed < 200; seed++) {
        for (var depth = 1; depth <= 60; depth++) {
          final p = factory.build(GameRandom(seed * 31 + depth), depth);
          counts.putIfAbsent(p.kind, () => <int>{}).add(p.options.length);
        }
      }
      // Grid logic offers only the values on its board, so its count follows the
      // board size: three values on a 3x3, four on a 4x4.
      expect(counts[PuzzleKind.gridLogic], <int>{3, 4});
      for (final kind in PuzzleKind.values.where((k) => k != PuzzleKind.gridLogic)) {
        expect(counts[kind], <int>{4}, reason: '$kind option count varied');
      }
    });
  });

  group('sequence puzzles are solvable', () {
    test('the answer always follows the shown rule', () {
      for (var depth = 1; depth <= 60; depth++) {
        for (var seed = 0; seed < 40; seed++) {
          final rng = GameRandom(seed * 104729 + depth);
          final puzzle = const SequenceGenerator().generate(rng, Difficulty(depth));
          final terms = _sequenceTerms(puzzle);
          final answer = int.parse(puzzle.solution.text!);

          // Exactly one rule may fit. If two did, the player would have no way
          // to tell which pattern is in play and two answers would be
          // defensible.
          final matching = matchingRules(terms);
          expect(
            matching,
            hasLength(1),
            reason:
                'terms $terms at depth $depth seed $seed fit '
                '${matching.map((r) => r.label).toList()}',
          );
          expect(
            matching.single.predict(terms),
            answer,
            reason:
                'rule ${matching.single.label} fits $terms but predicts '
                '${matching.single.predict(terms)} instead of $answer',
          );
        }
      }
    });

    test('no wrong option is a number from the series', () {
      for (var seed = 0; seed < 300; seed++) {
        final puzzle = const SequenceGenerator().generate(
          GameRandom(seed),
          const Difficulty(20),
        );
        final terms = _sequenceTerms(puzzle).toSet();
        for (var i = 0; i < puzzle.options.length; i++) {
          if (i == puzzle.solutionIndex) continue;
          final value = int.parse(puzzle.options[i].text!);
          expect(
            terms,
            isNot(contains(value)),
            reason: 'wrong option $value repeats a visible term',
          );
        }
      }
    });
  });

  group('make 24 puzzles are solvable', () {
    test('24 is always reachable and no distractor is', () {
      for (var depth = 1; depth <= 60; depth++) {
        for (var seed = 0; seed < 25; seed++) {
          final rng = GameRandom(seed * 31 + depth);
          final puzzle = const Make24Generator().generate(rng, Difficulty(depth));
          final numbers = (puzzle.body as TokenRowBody).tokens
              .map((t) => int.parse(t.text!))
              .toList();
          final tag = 'depth=$depth seed=$seed numbers=$numbers';

          expect(numbers, hasLength(4), reason: tag);
          expect(
            TargetSolver.canReach(numbers, 24),
            isTrue,
            reason: '$tag has no solution',
          );

          final reachable = TargetSolver.reachable(numbers);
          for (var i = 0; i < puzzle.options.length; i++) {
            if (i == puzzle.solutionIndex) continue;
            final value = int.parse(puzzle.options[i].text!);
            expect(
              reachable.any((v) => (v - value).abs() < 1e-9),
              isFalse,
              reason:
                  '$tag: distractor $value is also achievable, '
                  'so the puzzle has two answers',
            );
          }
          expect(puzzle.solution.text, '24', reason: tag);
        }
      }
    });

    test('the exact solver agrees with a hand-checked case', () {
      expect(TargetSolver.canReach([3, 3, 8, 8], 24), isTrue); // 8/(3-8/3)
      expect(TargetSolver.canReach([1, 2, 3, 4], 24), isTrue); // 1*2*3*4
      expect(TargetSolver.canReach([1, 1, 1, 1], 24), isFalse);
      expect(TargetSolver.canReach([5, 5, 5, 5], 24), isTrue); // 5*5-5/5
      expect(TargetSolver.canReach([1, 1, 1, 2], 24), isFalse);
      expect(TargetSolver.canReach([4, 4, 8, 8], 24), isTrue);
      // Division matters here: 3*3*3 = 27, and only 3/3 gets to 24.
      expect(TargetSolver.needsDivision([3, 3, 8, 8], 24), isTrue);
      expect(TargetSolver.needsDivision([1, 2, 3, 4], 24), isFalse);
      // A division-free search must not be able to use a fraction at all.
      expect(TargetSolver.canReach([3, 3, 8, 8], 24, allowDivision: false), isFalse);
    });

    test('division is required once the run is deep enough', () {
      var sawDivision = 0;
      for (var seed = 0; seed < 40; seed++) {
        final puzzle = const Make24Generator().generate(
          GameRandom(seed),
          const Difficulty(40),
        );
        final numbers = (puzzle.body as TokenRowBody).tokens
            .map((t) => int.parse(t.text!))
            .toList();
        if (TargetSolver.needsDivision(numbers, 24)) sawDivision++;
      }
      expect(sawDivision, greaterThan(20));
    });
  });

  group('grid logic puzzles have exactly one answer', () {
    /// Fills [cells] with [value] wherever it is blank and returns the result.
    List<String> filledWith(List<Token> cells, String value) => <String>[
      for (final cell in cells) cell.isBlank ? value : cell.text!,
    ];

    bool isLatinSquare(List<String> values, int size) {
      for (var r = 0; r < size; r++) {
        final row = <String>{};
        for (var c = 0; c < size; c++) {
          row.add(values[r * size + c]);
        }
        if (row.length != size) return false;
      }
      for (var c = 0; c < size; c++) {
        final col = <String>{};
        for (var r = 0; r < size; r++) {
          col.add(values[r * size + c]);
        }
        if (col.length != size) return false;
      }
      return true;
    }

    test('the grid is a Latin square with one forced answer', () {
      for (var depth = 1; depth <= 80; depth++) {
        for (var seed = 0; seed < 20; seed++) {
          final rng = GameRandom(seed * 613 + depth);
          final puzzle = const GridGenerator().generate(rng, Difficulty(depth));
          final body = puzzle.body as TokenGridBody;
          final size = body.cols;
          final tag = 'depth=$depth seed=$seed size=$size';

          expect(body.rows, size, reason: tag);
          expect(body.cells, hasLength(size * size), reason: tag);

          final blankIndices = <int>[
            for (var i = 0; i < size * size; i++)
              if (body.cells[i].isBlank) i,
          ];
          expect(blankIndices, isNotEmpty, reason: '$tag has no blank');

          // At most one blank per row and per column, or a row would be
          // under-constrained and more than one option could fit.
          for (var r = 0; r < size; r++) {
            final rowBlanks = <int>[
              for (var c = 0; c < size; c++)
                if (body.cells[r * size + c].isBlank) 1,
            ].length;
            expect(
              rowBlanks,
              lessThanOrEqualTo(1),
              reason: '$tag hides two cells in row $r',
            );
            if (rowBlanks == 0) {
              final known = <String>{
                for (var c = 0; c < size; c++) body.cells[r * size + c].text!,
              };
              expect(known, hasLength(size), reason: '$tag row $r: $known');
            }
          }
          final blankRows = blankIndices.map((i) => i ~/ size).toSet();
          final blankCols = blankIndices.map((i) => i % size).toSet();
          if (blankIndices.length > 1) {
            expect(
              blankRows,
              hasLength(blankIndices.length),
              reason: '$tag blanks share a row',
            );
            expect(
              blankCols,
              hasLength(blankIndices.length),
              reason: '$tag blanks share a column',
            );
          }

          // The blanks are hidden, so their values cannot be read back. The
          // observable equivalent of "every blank carries the answer" is that
          // filling all of them with the answer yields a valid square, which is
          // exactly what the next two assertions check.
          final answer = puzzle.solution.text!;
          expect(
            isLatinSquare(filledWith(body.cells, answer), size),
            isTrue,
            reason: '$tag answer $answer does not complete the square',
          );
          // ...and no other option does.
          for (var i = 0; i < puzzle.options.length; i++) {
            if (i == puzzle.solutionIndex) continue;
            expect(
              isLatinSquare(filledWith(body.cells, puzzle.options[i].text!), size),
              isFalse,
              reason: '$tag: option ${puzzle.options[i].text} also works',
            );
          }

          // The options are exactly the values in play, so nothing on the card
          // is left to rule a fourth answer out.
          expect(
            puzzle.options.map((t) => t.text!).toSet(),
            filledWith(body.cells, answer).toSet(),
            reason: '$tag options must be the grid values',
          );
        }
      }
    });

    test('the board grows with depth, which is what makes the content grow', () {
      final small =
          const GridGenerator().generate(GameRandom(1), const Difficulty(1)).body
              as TokenGridBody;
      final large =
          const GridGenerator().generate(GameRandom(1), const Difficulty(60)).body
              as TokenGridBody;
      expect(small.cols, 3);
      expect(large.cols, 4);
      expect(Difficulty(1).gridBlanks, lessThan(Difficulty(60).gridBlanks));
    });
  });

  group('memory puzzles are answerable', () {
    test('the answer cell held the asked symbol, decoys were also lit', () {
      for (var depth = 1; depth <= 60; depth++) {
        for (var seed = 0; seed < 25; seed++) {
          final rng = GameRandom(seed * 97 + depth);
          final puzzle = const MemoryGenerator().generate(rng, Difficulty(depth));
          final grid = (puzzle.body as TokenGridBody);
          final tag = 'depth=$depth seed=$seed';

          expect(grid.flashMs, isNotNull, reason: tag);
          expect(grid.revealLabel, isNotNull, reason: tag);
          expect(grid.cells, hasLength(9), reason: tag);

          // The asked symbol must appear exactly once, so the answer is unique.
          final matching = <int>[
            for (var i = 0; i < 9; i++)
              if (grid.cells[i].shape == grid.revealLabel!.shape) i,
          ];
          expect(
            matching,
            hasLength(1),
            reason: '$tag asks about a symbol seen ${matching.length} times',
          );

          // The answer letter must point at that cell.
          final answerCell = cellLabels.indexOf(puzzle.solution.text!);
          expect(answerCell, matching.single, reason: tag);

          // Every option cell must have been lit, so "which one was empty"
          // is never a winning strategy.
          for (final option in puzzle.options) {
            final cell = cellLabels.indexOf(option.text!);
            expect(cell, inInclusiveRange(0, 8), reason: tag);
            expect(
              grid.cells[cell].isGlyph,
              isTrue,
              reason: '$tag option ${option.text} points at an unlit cell',
            );
          }
        }
      }
    });

    test('the flash shrinks and the symbol count grows with depth', () {
      final early = const MemoryGenerator().generate(GameRandom(1), const Difficulty(1));
      final late = const MemoryGenerator().generate(GameRandom(1), const Difficulty(50));
      final earlyMs = (early.body as TokenGridBody).flashMs!;
      final lateMs = (late.body as TokenGridBody).flashMs!;
      expect(lateMs, lessThan(earlyMs));

      final litEarly = (early.body as TokenGridBody).cells.where((t) => t.isGlyph).length;
      final litLate = (late.body as TokenGridBody).cells.where((t) => t.isGlyph).length;
      expect(litLate, greaterThanOrEqualTo(litEarly));
    });
  });

  group('odd-one-out puzzles have one defensible answer', () {
    test('exactly three options match and one differs', () {
      for (var depth = 1; depth <= 60; depth++) {
        for (var seed = 0; seed < 25; seed++) {
          final rng = GameRandom(seed * 53 + depth);
          final puzzle = const OddOneGenerator().generate(rng, Difficulty(depth));
          final odd = puzzle.solution;
          final tag = 'depth=$depth seed=$seed';

          expect(
            puzzle.options.where((t) => t != odd).length,
            3,
            reason: '$tag: the three "normal" options must be identical',
          );
          // Rotation is only ever changed on a shape where it is visible.
          if (odd.rotation != 0) {
            expect(
              puzzle.solution.shape,
              isIn(const <ShapeKind>[
                ShapeKind.triangle,
                ShapeKind.arrow,
                ShapeKind.drop,
                ShapeKind.moon,
                ShapeKind.bolt,
              ]),
              reason: '$tag rotates a symmetric shape, which is invisible',
            );
          }
        }
      }
    });

    test('early puzzles differ in more ways than late ones', () {
      int differences(Token t, Token base) {
        var n = 0;
        if (t.shape != base.shape) n++;
        if (t.color != base.color) n++;
        if (t.scale != base.scale) n++;
        if (t.rotation != base.rotation) n++;
        return n;
      }

      for (var depth = 1; depth <= 3; depth++) {
        for (var seed = 0; seed < 20; seed++) {
          final puzzle = const OddOneGenerator().generate(
            GameRandom(seed),
            Difficulty(depth),
          );
          final base = puzzle.options.firstWhere((t) => t != puzzle.solution);
          expect(
            differences(puzzle.solution, base),
            greaterThanOrEqualTo(2),
            reason: 'depth $depth should be obvious',
          );
        }
      }
      for (var depth = 20; depth <= 60; depth++) {
        for (var seed = 0; seed < 20; seed++) {
          final puzzle = const OddOneGenerator().generate(
            GameRandom(seed),
            Difficulty(depth),
          );
          final base = puzzle.options.firstWhere((t) => t != puzzle.solution);
          expect(
            differences(puzzle.solution, base),
            1,
            reason: 'depth $depth should differ in exactly one way',
          );
        }
      }
    });
  });

  group('pattern puzzles', () {
    test('the cycle repeats and the answer is the next beat', () {
      for (var depth = 1; depth <= 60; depth++) {
        for (var seed = 0; seed < 25; seed++) {
          final rng = GameRandom(seed * 4099 + depth);
          final puzzle = const PatternGenerator().generate(rng, Difficulty(depth));
          final shown = (puzzle.body as TokenRowBody).tokens;
          final tag = 'depth=$depth seed=$seed';

          expect(shown.last.isBlank, isTrue, reason: '$tag must end in a blank');
          final filled = shown.sublist(0, shown.length - 1);
          expect(filled.length, greaterThanOrEqualTo(3), reason: tag);

          // Find the shortest cycle that explains the shown beats.
          int? period;
          for (var p = 1; p <= filled.length ~/ 2; p++) {
            var ok = true;
            for (var i = p; i < filled.length; i++) {
              if (filled[i] != filled[i - p]) {
                ok = false;
                break;
              }
            }
            if (ok) {
              period = p;
              break;
            }
          }
          expect(period, isNotNull, reason: '$tag shows no repeating cycle');
          expect(
            puzzle.solution,
            filled[period!],
            reason:
                '$tag: the next beat should be the one after '
                '${filled.sublist(0, period)}',
          );

          // A wrong option may repeat an earlier beat, which is a fair decoy
          // the player rules out by position. What must never happen is two
          // options that both satisfy the rule.
          for (var i = 0; i < puzzle.options.length; i++) {
            if (i == puzzle.solutionIndex) continue;
            expect(
              puzzle.options[i],
              isNot(puzzle.solution),
              reason: '$tag: wrong option matches the answer',
            );
          }
        }
      }
    });
  });

  group('puzzle factory rotation', () {
    test('the first three depths are the scripted intro', () {
      final factory = PuzzleFactory();
      expect(
        [for (var d = 1; d <= 3; d++) factory.pickKind(GameRandom(5), d)],
        <PuzzleKind>[PuzzleKind.sequence, PuzzleKind.pattern, PuzzleKind.oddOne],
      );
    });

    test('the same kind never lands twice in a row', () {
      final factory = PuzzleFactory();
      for (var seed = 0; seed < 60; seed++) {
        final rng = GameRandom(seed);
        PuzzleKind? last;
        for (var depth = 1; depth <= 80; depth++) {
          final kind = factory.pickKind(rng, depth, lastKind: last);
          if (depth > 3) {
            expect(kind, isNot(last), reason: 'seed $seed depth $depth repeated');
          }
          last = kind;
        }
      }
    });

    test('harder templates only appear once unlocked', () {
      final factory = PuzzleFactory();
      for (var seed = 0; seed < 40; seed++) {
        final rng = GameRandom(seed);
        for (var depth = 1; depth <= 5; depth++) {
          expect(
            factory.pickKind(rng, depth),
            isNot(PuzzleKind.make24),
            reason: 'make24 appeared at depth $depth',
          );
        }
        for (var depth = 1; depth <= 4; depth++) {
          expect(factory.pickKind(rng, depth), isNot(PuzzleKind.gridLogic));
        }
        for (var depth = 1; depth <= 5; depth++) {
          expect(factory.pickKind(rng, depth), isNot(PuzzleKind.memory));
        }
      }
    });

    test('boss rounds favour the slower templates', () {
      final factory = PuzzleFactory();
      final counts = <PuzzleKind, int>{};
      for (var seed = 0; seed < 200; seed++) {
        final kind = factory.pickKind(GameRandom(seed), 30, boss: true);
        counts[kind] = (counts[kind] ?? 0) + 1;
      }
      final hard =
          (counts[PuzzleKind.make24] ?? 0) +
          (counts[PuzzleKind.memory] ?? 0) +
          (counts[PuzzleKind.gridLogic] ?? 0);
      expect(hard, greaterThan(200 ~/ 2));
    });
  });

  group('determinism', () {
    test('the same seed replays the same run', () {
      List<String> run(int seed) {
        final factory = PuzzleFactory();
        final rng = GameRandom(seed);
        PuzzleKind? last;
        final out = <String>[];
        for (var depth = 1; depth <= 30; depth++) {
          final p = factory.build(rng, depth, lastKind: last, boss: depth % 10 == 0);
          out.add('${p.kind}:${p.solution.text ?? p.solution.shape}');
          last = p.kind;
        }
        return out;
      }

      expect(run(12345), run(12345));
      expect(run(12345), isNot(run(54321)));
    });

    test('daily seeds differ per day but are stable', () {
      final today = DateTime(2026, 3, 14);
      expect(dailySeedFor(today), dailySeedFor(DateTime(2026, 3, 14, 23, 59)));
      expect(dailySeedFor(today), isNot(dailySeedFor(DateTime(2026, 3, 15))));
    });
  });
}
