import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:weiqi/game.dart';
import 'package:weiqi/game_controller.dart';
import 'package:weiqi/local_store.dart';
import 'package:weiqi/native_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled KataGo evaluates, replays and scores on Android', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final privateFiles = await LocalStore.open();
      final scratch = await privateFiles.directory.createTemp('engine_test.');
      NativeEngine? engine;
      try {
        final paths = await LocalStore(scratch).prepareEngine();
        engine = await NativeEngine.start(paths.model, paths.config, 9);
        final kataGo = engine;
        var token = 0;
        for (final size in boardSizes) {
          await kataGo.reset(size, []);
          for (final tier in Difficulty.values) {
            final report = await kataGo.search(++token, tier.budgetFor(size));
            final candidates = report!.candidates;
            expect(candidates, isNotEmpty);
            expect(report.estimate.whiteLead, isNotNull);
            expect(report.estimate.whiteOwnership, hasLength(size * size));
            expect(
              report.estimate.whiteOwnership,
              everyElement(inInclusiveRange(-1, 1)),
            );
            final chosen = candidates.first.point;
            final position = await kataGo.play(chosen);
            if (chosen != pass) {
              expect(position.stones[chosen], 1 + tier.index % 2);
            }
          }

          final cancelled = kataGo.search(
            ++token,
            const SearchBudget(100000, 5, 0),
          );
          kataGo.cancel(token);
          expect(await cancelled, isNull);
          expect(
            (await kataGo.search(
              ++token,
              Difficulty.beginner.budgetFor(size),
            ))?.candidates,
            isNotEmpty,
          );

          await kataGo.reset(size, []);
          expect((await kataGo.play(pass)).result, isNull);
          final scored = (await kataGo.play(pass)).result!;
          expect(scored.winner, Stone.white);
          expect(scored.margin, 7.5);
        }

        final ko = await kataGo.reset(9, [1, 2, 9, 12, 19, 20, 80, 10, 11]);
        expect(ko.stones[10], 0);
        expect(ko.stones[11], 1);
        await expectLater(kataGo.play(11), throwsA(isA<IllegalMove>()));
        await expectLater(kataGo.play(10), throwsA(isA<IllegalMove>()));
        await kataGo.play(65);
        await kataGo.play(78);
        expect((await kataGo.play(10)).stones[11], 0);

        await kataGo.reset(9, [1, 80, 9, 79, 11, 78, 19]);
        await expectLater(kataGo.play(10), throwsA(isA<IllegalMove>()));
        await expectLater(
          kataGo.setModel('${scratch.path}/missing.bin.gz', 9),
          throwsStateError,
        );
        expect(
          (await kataGo.search(
            ++token,
            Difficulty.beginner.budgetFor(9),
          ))?.candidates,
          isNotEmpty,
        );

        for (final leader in Stone.values) {
          final moves = [
            for (var point = 0; point < 36; point++)
              if (leader == Stone.black) ...[point, pass] else ...[pass, point],
          ];
          await kataGo.reset(9, moves);
          final estimate = await kataGo.search(
            ++token,
            const SearchBudget(48, 1.2, 0),
            includeCandidates: false,
          );
          expect(estimate!.candidates, isEmpty);
          expect(
            estimate.estimate.whiteLead,
            leader == Stone.black ? lessThan(0) : greaterThan(0),
          );
          expect(
            estimate.estimate.whiteOwnership[4],
            leader == Stone.black ? lessThan(-0.2) : greaterThan(0.2),
          );
          final position = await kataGo.play(80);
          expect(position.stones.take(36), everyElement(leader.index + 1));
          expect(position.stones[80], 1);
        }
      } finally {
        await engine?.close();
        await scratch.delete(recursive: true);
      }
    });
  });

  testWidgets('search changes and restored AI turns commit exactly once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final privateFiles = await LocalStore.open();
      final scratch = await privateFiles.directory.createTemp('game_test.');
      final store = LocalStore(scratch);
      final game = GameController(store);
      try {
        await store.write(
          const GameRecord(
            size: 19,
            difficulty: Difficulty.advanced,
            moves: [180],
          ),
        );
        await game.load();
        expect(game.searching, isTrue);
        await game.setDifficulty(Difficulty.beginner);

        final deadline = Stopwatch()..start();
        while (!game.canPlay && deadline.elapsed < const Duration(seconds: 8)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(game.canPlay, isTrue, reason: game.notice);
        expect(game.record.moves, hasLength(2));
        expect(game.record.moves.first, 180);
        expect((await store.read())!.difficulty, Difficulty.beginner);

        await game.setDifficulty(Difficulty.advanced);
        await game.play(game.position!.stones.indexOf(0));
        expect(game.searching, isTrue);
        await game.undo();
        expect(game.record.moves, hasLength(2));

        await game.play(game.position!.stones.indexOf(0));
        expect(game.searching, isTrue);
        await game.startGame(13, Stone.black, Difficulty.intermediate);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        expect(game.canPlay, isTrue, reason: game.notice);
        expect(game.position!.size, 13);
        expect(game.record.moves, isEmpty);
        expect((await store.read())!.moves, isEmpty);
      } finally {
        game.dispose();
        await scratch.delete(recursive: true);
      }
    });
  });

  testWidgets('midgame estimation keeps the game and the AI turn intact', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final privateFiles = await LocalStore.open();
      final scratch = await privateFiles.directory.createTemp('lead_test.');
      final store = LocalStore(scratch);
      final game = GameController(store);
      try {
        const opening = [40, 39];
        await store.write(const GameRecord(moves: opening));
        await game.load();
        game.selectPoint(41);
        final estimate = await game.estimatePosition();
        expect(estimate?.whiteLead, isNotNull);
        expect(estimate?.whiteOwnership, hasLength(81));
        expect(game.selectedPoint, 41);
        expect(game.record.moves, opening);
        expect((await store.read())!.moves, opening);

        final cancelled = game.estimatePosition();
        game.cancelEstimate();
        expect(await cancelled, isNull);
        await game.confirmSelection();
        expect(game.searching, isTrue);
        final duringAi = game.estimatePosition();
        game.cancelEstimate();
        final aiEstimate = await duringAi;
        expect(aiEstimate?.whiteLead, isNotNull);
        expect(aiEstimate?.whiteOwnership, hasLength(81));

        final deadline = Stopwatch()..start();
        while (!game.canPlay && deadline.elapsed < const Duration(seconds: 8)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(game.canPlay, isTrue, reason: game.notice);
        expect(game.record.moves, hasLength(4));
        expect(game.record.moves.take(3), [...opening, 41]);
        expect((await store.read())!.moves, game.record.moves);
      } finally {
        game.dispose();
        await scratch.delete(recursive: true);
      }
    });
  });

  testWidgets('precise placement persists only the confirmed intersection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final privateFiles = await LocalStore.open();
      final scratch = await privateFiles.directory.createTemp(
        'placement_test.',
      );
      final store = LocalStore(scratch);
      final game = GameController(store);
      try {
        await game.load();
        await game.startGame(19, Stone.black, Difficulty.beginner);
        game.selectPoint(0);
        game.shiftSelection(-1, 0);
        game.shiftSelection(0, -1);
        expect(game.selectedPoint, 0);
        game.shiftSelection(1, 0);
        game.shiftSelection(0, 1);
        expect(game.selectedPoint, 20);
        game.shiftSelection(0, -1);
        game.shiftSelection(-1, 0);
        expect(game.selectedPoint, 0);
        expect(game.record.moves, isEmpty);
        expect((await store.read())!.moves, isEmpty);

        game.selectPoint(360);
        game.shiftSelection(1, 0);
        game.shiftSelection(0, 1);
        expect(game.selectedPoint, 360);
        game.selectPoint(null);
        await game.confirmSelection();
        expect(game.record.moves, isEmpty);

        game.selectPoint(0);
        game.shiftSelection(1, 0);
        game.shiftSelection(0, 1);
        await game.confirmSelection();
        expect(game.selectedPoint, isNull);
        expect((await store.read())!.moves.first, 20);

        final deadline = Stopwatch()..start();
        while (!game.canPlay && deadline.elapsed < const Duration(seconds: 8)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(game.canPlay, isTrue, reason: game.notice);
        game.selectPoint(20);
        expect(game.canConfirmSelection, isFalse);
        await game.confirmSelection();
        expect(game.record.moves, hasLength(2));
        await game.undo();
        expect(game.selectedPoint, isNull);
        expect(game.record.moves, isEmpty);

        game.selectPoint(360);
        await game.startGame(13, Stone.black, Difficulty.intermediate);
        expect(game.selectedPoint, isNull);
        game.selectPoint(10);
        await game.startGame(13, Stone.black, Difficulty.intermediate);
        expect(game.selectedPoint, isNull);
      } finally {
        game.dispose();
        await scratch.delete(recursive: true);
      }
    });
  });

  testWidgets('all four models can search and switching preserves the game', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final privateFiles = await LocalStore.open();
      final scratch = await privateFiles.directory.createTemp('model_test.');
      final store = LocalStore(scratch);
      final game = GameController(store);
      try {
        const opening = [180, 181];
        const saved = GameRecord(
          size: 19,
          difficulty: Difficulty.advanced,
          moves: opening,
        );
        final legacy = saved.toJson()..remove('model');
        expect(GameRecord.fromJson(legacy).model, AiModel.b6c96);
        await store.write(saved);
        await game.load();

        for (final model in AiModel.values) {
          await game.setModel(model);
          expect(game.record.model, model, reason: game.notice);
          expect(game.record.moves, opening);
          expect(game.position!.stones[180], 1);
          expect(game.position!.stones[181], 2);
          expect((await store.read())!.model, model);

          await game.play(0);
          final deadline = Stopwatch()..start();
          while (game.searching || game.busy) {
            if (deadline.elapsed > const Duration(seconds: 12)) break;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          expect(game.canPlay, isTrue, reason: '${model.name}: ${game.notice}');
          expect(game.record.moves, hasLength(4));
          expect((await store.read())!.model, model);
          await game.undo();
        }

        await game.play(0);
        expect(game.searching, isTrue);
        await game.setModel(AiModel.b6c96);
        final deadline = Stopwatch()..start();
        while (game.searching || game.busy) {
          if (deadline.elapsed > const Duration(seconds: 8)) break;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(game.canPlay, isTrue, reason: game.notice);
        expect(game.record.moves, hasLength(4));
        expect((await store.read())!.model, AiModel.b6c96);
      } finally {
        game.dispose();
        await scratch.delete(recursive: true);
      }
    });
  });
}
