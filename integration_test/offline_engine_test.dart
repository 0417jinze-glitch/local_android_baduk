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
            final candidates = await kataGo.search(
              ++token,
              tier.budgetFor(size),
            );
            expect(candidates, isNotEmpty);
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
          expect(await cancelled, isEmpty);
          expect(
            await kataGo.search(++token, Difficulty.beginner.budgetFor(size)),
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
}
