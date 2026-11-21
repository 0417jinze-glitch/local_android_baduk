import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'game.dart';
import 'local_store.dart';
import 'native_engine.dart';

const _illegalMoveNotice = '这里不能落子，请选择其他交叉点。';

class GameController extends ChangeNotifier {
  GameController([this._store]);

  final _random = Random();
  LocalStore? _store;
  NativeEngine? _engine;
  GameRecord _record = const GameRecord();
  Position? _position;
  int? _selectedPoint;
  String? _notice;
  bool _busy = false;
  bool _searching = false;
  bool _disposed = false;
  int _searchToken = 0;
  Completer<void>? _activeChange;

  GameRecord get record => _record;
  Position? get position => _position;
  int? get selectedPoint => _selectedPoint;
  String? get notice => _notice;
  bool get busy => _busy;
  bool get searching => _searching;
  bool get ready => _position != null;
  bool get canPlay =>
      ready &&
      !_busy &&
      _record.result == null &&
      _position!.next == _record.human;
  bool get canConfirmSelection {
    final point = _selectedPoint;
    return canPlay && point != null && _position!.stones[point] == 0;
  }

  bool get canUndo =>
      ready &&
      !_busy &&
      (_record.result?.kind == ResultKind.resignation || _lastHumanTurn >= 0);
  bool get canRetrySearch =>
      ready &&
      !_busy &&
      !_searching &&
      _record.result == null &&
      _position!.next != _record.human &&
      _notice != null;

  int get _lastHumanTurn {
    final last = _record.moves.length - 1;
    return last.isEven == (_record.human == Stone.black) ? last : last - 1;
  }

  Future<void> load() async {
    if (_busy || _disposed || ready) return;
    _busy = true;
    _notice = null;
    notifyListeners();

    NativeEngine? engine;
    try {
      await _engine?.close();
      _engine = null;
      final store = _store ?? await LocalStore.open();
      var restored = const GameRecord();
      try {
        restored = await store.read() ?? restored;
      } catch (error) {
        debugPrint('Saved game could not be read: $error');
        _notice = '上一局存档无法读取，已打开空棋盘。';
      }
      final files = await store.prepareEngine();
      if (_disposed) return;
      engine = await NativeEngine.start(
        files.model,
        files.config,
        restored.size,
      );

      Position position;
      try {
        position = await engine.reset(restored.size, restored.moves);
        _validateResult(restored, position.result);
      } catch (error) {
        debugPrint('Saved moves could not be replayed: $error');
        restored = const GameRecord();
        position = await engine.reset(restored.size, restored.moves);
        _notice = '上一局棋谱无法恢复，已打开空棋盘。';
      }

      if (_disposed) return;
      _engine = engine;
      _store = store;
      _record = restored;
      _position = position;
      engine = null;
    } catch (error) {
      debugPrint('KataGo initialization failed: $error');
      _notice = '本地引擎加载失败，请重试。';
    } finally {
      if (engine != null) unawaited(_close(engine));
      _busy = false;
      if (!_disposed) {
        notifyListeners();
        _startSearch();
      }
    }
  }

  Future<void> startGame(int size, Stone human, Difficulty difficulty) =>
      _change(() async {
        final position = await _engine!.reset(size, const []);
        await _commit(
          GameRecord(size: size, human: human, difficulty: difficulty),
          position,
        );
      });

  Future<void> setDifficulty(Difficulty difficulty) async {
    if (difficulty == _record.difficulty) return;
    await _change(
      () => _commit(
        GameRecord(
          size: _record.size,
          human: _record.human,
          difficulty: difficulty,
          moves: _record.moves,
          result: _record.result,
        ),
        _position!,
      ),
    );
  }

  Future<void> play(int point) async {
    if (canPlay) await _change(() => _play(point));
  }

  void selectPoint(int? point) {
    if (!canPlay || point == _selectedPoint) return;
    if (point != null && (point < 0 || point >= _position!.stones.length)) {
      return;
    }
    _selectedPoint = point;
    if (_notice == _illegalMoveNotice) _notice = null;
    notifyListeners();
  }

  int? selectionNeighbor(int dx, int dy) {
    final point = _selectedPoint;
    if (!canPlay || point == null) return null;
    final size = _position!.size;
    final x = point % size + dx;
    final y = point ~/ size + dy;
    if (x < 0 || x >= size || y < 0 || y >= size) return null;
    return y * size + x;
  }

  void shiftSelection(int dx, int dy) {
    final point = selectionNeighbor(dx, dy);
    if (point != null) selectPoint(point);
  }

  Future<void> confirmSelection() async {
    final point = _selectedPoint;
    if (point != null && canConfirmSelection) await play(point);
  }

  Future<void> undo() async {
    if (!canUndo) return;
    await _change(() async {
      final moves = _record.result?.kind == ResultKind.resignation
          ? _record.moves
          : List<int>.unmodifiable(_record.moves.take(_lastHumanTurn));
      final position = await _engine!.reset(_record.size, moves);
      await _commit(_withMoves(moves), position);
    });
  }

  Future<void> resign() async {
    if (_record.result != null) return;
    await _change(() async {
      if (_record.result != null) return;
      await _commit(
        _withMoves(
          _record.moves,
          GameResult(ResultKind.resignation, _record.human.opponent),
        ),
        _position!,
      );
    });
  }

  void retrySearch() {
    if (!canRetrySearch) return;
    _notice = null;
    _startSearch();
  }

  GameRecord _withMoves(List<int> moves, [GameResult? result]) => GameRecord(
    size: _record.size,
    human: _record.human,
    difficulty: _record.difficulty,
    moves: moves,
    result: result,
  );

  Future<void> _play(int point) async {
    final position = await _engine!.play(point);
    final moves = List<int>.unmodifiable([..._record.moves, point]);
    await _commit(_withMoves(moves, position.result), position);
  }

  Future<void> _commit(GameRecord record, Position position) async {
    await _store!.write(record);
    if (!identical(position, _position) || record.result != null) {
      _selectedPoint = null;
    }
    _record = record;
    _position = position;
  }

  Future<void> _change(Future<void> Function() operation) async {
    while (_activeChange != null) {
      await _activeChange!.future;
    }
    if (_busy || _disposed || !ready) return;
    final completed = Completer<void>();
    _activeChange = completed;
    _busy = true;
    _notice = null;
    _cancelSearch();
    notifyListeners();

    try {
      await operation();
    } on IllegalMove {
      _notice = _illegalMoveNotice;
    } catch (error) {
      debugPrint('Game operation failed: $error');
      try {
        await _engine!.reset(_record.size, _record.moves);
        _notice = '操作未能保存，已恢复当前对局。';
      } catch (error) {
        debugPrint('Game rollback failed: $error');
        _position = null;
        _selectedPoint = null;
        _notice = '本地对局暂时无法继续，请重试加载。';
      }
    } finally {
      _activeChange = null;
      _busy = false;
      completed.complete();
      if (!_disposed) {
        notifyListeners();
        _startSearch();
      }
    }
  }

  void _startSearch() {
    if (_disposed ||
        _busy ||
        _searching ||
        !ready ||
        _notice != null ||
        _record.result != null ||
        _position!.next == _record.human) {
      return;
    }
    final token = ++_searchToken;
    final budget = _record.difficulty.budgetFor(_record.size);
    _searching = true;
    notifyListeners();
    unawaited(_search(token, budget));
  }

  Future<void> _search(int token, SearchBudget budget) async {
    try {
      final candidates = await _engine!.search(token, budget);
      if (_disposed || token != _searchToken) return;
      if (candidates.isEmpty) {
        throw StateError('Unexpected search cancellation');
      }
      await _change(() => _play(budget.select(candidates, _random)));
    } catch (error) {
      if (_disposed || token != _searchToken) return;
      debugPrint('KataGo search failed: $error');
      _searching = false;
      _notice = 'AI 出棋失败，请重试。';
      notifyListeners();
    }
  }

  void _cancelSearch() {
    if (!_searching) return;
    _engine!.cancel(_searchToken);
    _searchToken++;
    _searching = false;
  }

  void _validateResult(GameRecord record, GameResult? actual) {
    final saved = record.result;
    if (saved?.kind == ResultKind.resignation) {
      if (actual == null && saved!.winner == record.human.opponent) return;
    } else if (saved?.kind == actual?.kind &&
        saved?.winner == actual?.winner &&
        saved?.margin == actual?.margin) {
      return;
    }
    throw const FormatException('Saved result does not match the move history');
  }

  Future<void> _close(NativeEngine engine) async {
    try {
      await engine.close();
    } catch (error) {
      debugPrint('KataGo worker could not close: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSearch();
    final engine = _engine;
    if (engine != null) unawaited(_close(engine));
    super.dispose();
  }
}
