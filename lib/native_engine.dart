import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'game.dart';

class IllegalMove implements Exception {
  const IllegalMove();
}

typedef SearchResult = ({double? whiteLead, List<Candidate> candidates});

class NativeEngine {
  NativeEngine._() {
    _events.listen(_onEvent);
  }

  final ReceivePort _events = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<Object?>> _pending = {};
  late final Isolate _worker;
  late final SendPort _workerPort;
  late final Pointer<Void> _handle;
  int _requestId = 0;
  int _latestSearch = 0;
  bool _closing = false;
  bool _alive = false;

  static Future<NativeEngine> start(
    String model,
    String config,
    int size,
  ) async {
    final engine = NativeEngine._();
    try {
      engine._worker = await Isolate.spawn(
        _runWorker,
        (engine._events.sendPort, model, config, size),
        onError: engine._events.sendPort,
        onExit: engine._events.sendPort,
        debugName: 'KataGo',
      );
      await engine._ready.future;
      return engine;
    } catch (_) {
      engine._events.close();
      rethrow;
    }
  }

  Future<Position> reset(int size, List<int> moves) async =>
      await _request(_Reset(size, moves)) as Position;

  Future<void> setModel(String path, int size) async {
    await _request(_SetModel(path, size));
  }

  Future<Position> play(int point) async =>
      await _request(_Play(point)) as Position;

  Future<SearchResult?> search(
    int token,
    SearchBudget budget, {
    bool includeCandidates = true,
  }) async {
    _latestSearch = token;
    return await _request(_Search(token, budget, includeCandidates))
        as SearchResult?;
  }

  void cancel(int token) {
    if (_alive && !_closing) _cancel(_handle, token);
  }

  Future<void> close() async {
    if (_closing) return;
    cancel(_latestSearch);
    _closing = true;
    try {
      if (_alive) await _request(const _Close());
    } finally {
      _worker.kill();
      _events.close();
    }
  }

  Future<Object?> _request(_Command command) {
    if (!_alive || (_closing && command is! _Close)) {
      return Future.error(StateError('KataGo worker is closed'));
    }
    final id = ++_requestId;
    final reply = Completer<Object?>();
    _pending[id] = reply;
    _workerPort.send((id, command));
    return reply.future;
  }

  void _onEvent(Object? message) {
    switch (message) {
      case (SendPort port, int address):
        _workerPort = port;
        _handle = Pointer.fromAddress(address);
        _alive = true;
        _ready.complete();
      case (int id, Object? value, Object? error):
        final reply = _pending.remove(id);
        if (error == null) {
          reply?.complete(value);
        } else {
          reply?.completeError(error);
        }
      case _:
        _alive = false;
        final error = StateError(
          message?.toString() ?? 'KataGo worker stopped',
        );
        if (!_ready.isCompleted) _ready.completeError(error);
        for (final reply in _pending.values) {
          reply.completeError(error);
        }
        _pending.clear();
    }
  }
}

sealed class _Command {
  const _Command();
}

class _Reset extends _Command {
  const _Reset(this.size, this.moves);
  final int size;
  final List<int> moves;
}

class _SetModel extends _Command {
  const _SetModel(this.path, this.size);
  final String path;
  final int size;
}

class _Play extends _Command {
  const _Play(this.point);
  final int point;
}

class _Search extends _Command {
  const _Search(this.token, this.budget, this.includeCandidates);
  final int token;
  final SearchBudget budget;
  final bool includeCandidates;
}

class _Close extends _Command {
  const _Close();
}

void _runWorker((SendPort, String, String, int) args) {
  final (output, model, config, size) = args;
  final bindings = _Bindings();
  final handle = using((arena) {
    const capacity = 1024;
    final error = arena<Char>(capacity);
    final handle = bindings.create(
      model.toNativeUtf8(allocator: arena),
      config.toNativeUtf8(allocator: arena),
      size,
      error,
      capacity,
    );
    if (handle == nullptr) {
      throw StateError(error.cast<Utf8>().toDartString());
    }
    return handle;
  });

  final inbox = ReceivePort();
  output.send((inbox.sendPort, handle.address));
  inbox.listen((message) {
    final (id, command) = message as (int, _Command);
    if (command is _Close) {
      bindings.destroy(handle);
      output.send((id, null, null));
      inbox.close();
      return;
    }
    try {
      final value = using(
        (arena) => _execute(bindings, handle, command, arena),
      );
      output.send((id, value, null));
    } catch (error) {
      output.send((id, null, error));
    }
  });
}

Object? _execute(
  _Bindings api,
  Pointer<Void> handle,
  _Command command,
  Arena arena,
) {
  void check(int status) {
    if (status < 0) throw StateError(api.error(handle).toDartString());
    if (status == 1) throw const IllegalMove();
  }

  switch (command) {
    case _SetModel(:final path, :final size):
      check(api.setModel(handle, path.toNativeUtf8(allocator: arena), size));
      return null;
    case _Reset(:final size, :final moves):
      final points = arena<Int32>(moves.length);
      points.asTypedList(moves.length).setAll(0, moves);
      final out = arena<_NativePosition>();
      check(api.reset(handle, size, points, moves.length, out));
      return out.ref.toPosition();
    case _Play(:final point):
      final out = arena<_NativePosition>();
      check(api.play(handle, point, out));
      return out.ref.toPosition();
    case _Search(:final token, :final budget, :final includeCandidates):
      final out = arena<_NativeSearchResult>();
      final status = api.search(
        handle,
        token,
        budget.visits,
        budget.seconds,
        includeCandidates ? 1 : 0,
        out,
      );
      if (status < 0) throw StateError(api.error(handle).toDartString());
      if (status == 0) return null;
      final result = out.ref;
      final lead = result.whiteLead;
      final candidates = List<Candidate>.generate(result.count, (index) {
        final move = result.candidates[index];
        return Candidate(move.point, move.visits, move.utility);
      });
      return (whiteLead: lead.isFinite ? lead : null, candidates: candidates);
    case _Close():
      throw StateError('Close must be handled by the worker');
  }
}

final class _NativePosition extends Struct {
  @Int32()
  external int size;

  @Int32()
  external int next;

  @Int32()
  external int finished;

  @Int32()
  external int winner;

  @Double()
  external double whiteMinusBlack;

  @Array(361)
  external Array<Uint8> stones;

  Position toPosition() => Position(
    size,
    Stone.values[next - 1],
    List<int>.generate(size * size, (point) => stones[point], growable: false),
    finished == 0
        ? null
        : GameResult(
            ResultKind.scored,
            winner == 0 ? null : Stone.values[winner - 1],
            whiteMinusBlack.abs(),
          ),
  );
}

final class _NativeCandidate extends Struct {
  @Int32()
  external int point;

  @Int32()
  external int visits;

  @Double()
  external double utility;
}

final class _NativeSearchResult extends Struct {
  @Double()
  external double whiteLead;

  @Int32()
  external int count;

  @Array(16)
  external Array<_NativeCandidate> candidates;
}

final _library = DynamicLibrary.open('libweiqi_katago.so');
final _cancel = _library
    .lookupFunction<
      Void Function(Pointer<Void>, Uint64),
      void Function(Pointer<Void>, int)
    >('weiqi_cancel', isLeaf: true);

class _Bindings {
  final create = _library
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Utf8>,
          Pointer<Utf8>,
          Int32,
          Pointer<Char>,
          Int32,
        ),
        Pointer<Void> Function(
          Pointer<Utf8>,
          Pointer<Utf8>,
          int,
          Pointer<Char>,
          int,
        )
      >('weiqi_create');

  final destroy = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('weiqi_destroy');

  final error = _library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('weiqi_error');

  final setModel = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32),
        int Function(Pointer<Void>, Pointer<Utf8>, int)
      >('weiqi_set_model');

  final reset = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Int32,
          Pointer<Int32>,
          Int32,
          Pointer<_NativePosition>,
        ),
        int Function(
          Pointer<Void>,
          int,
          Pointer<Int32>,
          int,
          Pointer<_NativePosition>,
        )
      >('weiqi_reset');

  final play = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<_NativePosition>),
        int Function(Pointer<Void>, int, Pointer<_NativePosition>)
      >('weiqi_play');

  final search = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Uint64,
          Int32,
          Double,
          Int32,
          Pointer<_NativeSearchResult>,
        ),
        int Function(
          Pointer<Void>,
          int,
          int,
          double,
          int,
          Pointer<_NativeSearchResult>,
        )
      >('weiqi_search');
}
