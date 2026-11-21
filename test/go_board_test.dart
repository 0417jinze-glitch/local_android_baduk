import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weiqi/game.dart';
import 'package:weiqi/go_board.dart';

void main() {
  testWidgets('the compact board frame keeps corner and center taps accurate', (
    tester,
  ) async {
    const width = 352.0;
    for (final size in boardSizes) {
      final selections = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              child: GoBoard(
                position: Position(
                  size,
                  Stone.black,
                  List.filled(size * size, 0),
                  null,
                ),
                lastPoint: null,
                selectedPoint: null,
                onSelect: selections.add,
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(GoBoard));
      for (final offset in const [
        Offset(5, 5),
        Offset(width - 5, 5),
        Offset(5, width - 5),
        Offset(width - 5, width - 5),
        Offset(width / 2, width / 2),
      ]) {
        await tester.tapAt(topLeft + offset);
      }

      expect(selections, [
        0,
        size - 1,
        size * (size - 1),
        size * size - 1,
        (size * size) ~/ 2,
      ], reason: '$size×$size board');
    }
  });
}
