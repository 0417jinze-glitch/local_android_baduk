import 'dart:math';

const boardSizes = [9, 13, 19];
const pass = -1;
const rules = 'chinese-ogs';
const komi = 7.5;

enum Stone {
  black('黑'),
  white('白');

  const Stone(this.label);

  final String label;

  Stone get opponent => this == black ? white : black;
}

enum AiModel {
  b6c96('kata1-b6c96-s175395328-d26788732.txt.gz', 4967720),
  b10c128('kata1-b10c128-s1141046784-d204142634.txt.gz', 14466254),
  b15c192('kata1-b15c192-s1672170752-d466197061.txt.gz', 48038914),
  b20c256x2('kata1-b20c256x2-s5303129600-d1228401921.bin.gz', 87358203);

  const AiModel(this.asset, this.assetBytes);

  final String asset;
  final int assetBytes;
}

enum Difficulty {
  beginner('初级'),
  intermediate('中级'),
  advanced('高级');

  const Difficulty(this.label);

  final String label;

  SearchBudget budgetFor(int size) => switch ((size, this)) {
    (9, beginner) => const SearchBudget(10, 0.7, 0.27),
    (9, intermediate) => const SearchBudget(32, 1.4, 0.07),
    (9, advanced) => const SearchBudget(96, 2.8, 0),
    (13, beginner) => const SearchBudget(9, 0.8, 0.26),
    (13, intermediate) => const SearchBudget(26, 1.6, 0.065),
    (13, advanced) => const SearchBudget(72, 3.0, 0),
    (19, beginner) => const SearchBudget(8, 1.0, 0.24),
    (19, intermediate) => const SearchBudget(22, 2.0, 0.06),
    (19, advanced) => const SearchBudget(60, 3.5, 0),
    _ => throw ArgumentError.value(size, 'size'),
  };
}

class SearchBudget {
  const SearchBudget(this.visits, this.seconds, this.utilityWindow);

  final int visits;
  final double seconds;
  final double utilityWindow;

  int select(List<Candidate> candidates, Random random) {
    final best = candidates.first;
    if (best.point == pass || utilityWindow == 0 || best.visits == 0) {
      return best.point;
    }

    final eligible = candidates
        .where(
          (move) =>
              move.point != pass &&
              move.visits > 0 &&
              best.utility - move.utility <= utilityWindow,
        )
        .toList();
    final weights = eligible.map((move) {
      final loss = max(0.0, best.utility - move.utility);
      return sqrt(move.visits) * exp(-2 * loss / utilityWindow);
    }).toList();
    var draw =
        random.nextDouble() * weights.fold(0.0, (sum, weight) => sum + weight);
    for (var index = 0; index < eligible.length; index++) {
      draw -= weights[index];
      if (draw < 0) return eligible[index].point;
    }
    return best.point;
  }
}

class Candidate {
  const Candidate(this.point, this.visits, this.utility);

  final int point;
  final int visits;
  final double utility;
}

class Position {
  const Position(this.size, this.next, this.stones, this.result);

  final int size;
  final Stone next;
  final List<int> stones;
  final GameResult? result;
}

enum ResultKind { scored, resignation }

class GameResult {
  const GameResult(this.kind, this.winner, [this.margin]);

  final ResultKind kind;
  final Stone? winner;
  final double? margin;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'winner': winner?.name,
    'margin': margin,
  };

  factory GameResult.fromJson(Map<String, dynamic> json) {
    final kind = ResultKind.values.byName(json['kind'] as String);
    final winner = json['winner'];
    final margin = (json['margin'] as num?)?.toDouble();
    if (kind == ResultKind.scored
        ? margin == null || !margin.isFinite || margin < 0
        : winner == null || margin != null) {
      throw const FormatException('Invalid game result');
    }
    return GameResult(
      kind,
      winner == null ? null : Stone.values.byName(winner as String),
      margin,
    );
  }
}

class GameRecord {
  const GameRecord({
    this.size = 9,
    this.human = Stone.black,
    this.difficulty = Difficulty.intermediate,
    this.model = AiModel.b6c96,
    this.moves = const [],
    this.result,
  });

  final int size;
  final Stone human;
  final Difficulty difficulty;
  final AiModel model;
  final List<int> moves;
  final GameResult? result;

  Map<String, Object?> toJson() => {
    'version': 1,
    'size': size,
    'human': human.name,
    'difficulty': difficulty.name,
    'model': model.name,
    'rules': rules,
    'komi': komi,
    'moves': moves,
    'result': result?.toJson(),
  };

  factory GameRecord.fromJson(Map<String, dynamic> json) {
    final size = json['size'] as int;
    if (json['version'] != 1 ||
        !boardSizes.contains(size) ||
        json['rules'] != rules ||
        json['komi'] != komi) {
      throw const FormatException('Unsupported saved game');
    }

    final moves = List<int>.unmodifiable(json['moves'] as List<dynamic>);
    if (moves.any((move) => move < pass || move >= size * size)) {
      throw const FormatException('Invalid saved move');
    }

    final result = json['result'] as Map<String, dynamic>?;
    final modelName = json['model'] as String?;
    return GameRecord(
      size: size,
      human: Stone.values.byName(json['human'] as String),
      difficulty: Difficulty.values.byName(json['difficulty'] as String),
      model: modelName == null
          ? AiModel.b6c96
          : AiModel.values.byName(modelName),
      moves: moves,
      result: result == null ? null : GameResult.fromJson(result),
    );
  }
}
