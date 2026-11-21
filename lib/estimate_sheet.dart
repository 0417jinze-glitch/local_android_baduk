import 'package:material_ui/material_ui.dart';

import 'game.dart';
import 'go_board.dart';

class EstimateSheet extends StatelessWidget {
  const EstimateSheet({
    required this.position,
    required this.turn,
    required this.lastPoint,
    required this.estimate,
    super.key,
  });

  final Position position;
  final int turn;
  final int? lastPoint;
  final Future<PositionEstimate?> estimate;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '局势判定',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text('第 $turn 手 · 已计入白贴 $komi 点'),
          const SizedBox(height: 6),
          FutureBuilder<PositionEstimate?>(
            future: estimate,
            builder: (context, snapshot) {
              final prediction = snapshot.data?.whiteOwnership;
              final ownership = prediction?.length == position.stones.length
                  ? prediction
                  : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(liveRegion: true, child: _summary(snapshot)),
                  const SizedBox(height: 10),
                  Semantics(
                    label: '势力图',
                    container: true,
                    child: GoBoard(
                      position: position,
                      lastPoint: lastPoint,
                      selectedPoint: null,
                      onSelect: null,
                      whiteOwnership: ownership,
                    ),
                  ),
                  if (ownership != null) ...[
                    const SizedBox(height: 14),
                    const Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _LegendItem(blackOwnershipMarker, '黑棋势力'),
                        _LegendItem(whiteOwnershipMarker, '白棋势力'),
                        _LegendItem(Color(0xFFE9BC7D), '归属未明'),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _summary(AsyncSnapshot<PositionEstimate?> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Flexible(child: Text('正在判定…')),
        ],
      );
    }
    final lead = snapshot.data?.whiteLead;
    if (lead == null) return const Text('暂时无法判定，请重试。');

    final points = lead.abs();
    if (points < 0.1) return const Text('局势接近均势');
    final leader = lead > 0 ? Stone.white : Stone.black;
    final stones = (points / 2).toStringAsFixed(1);
    return Text(
      '${leader.label}棋预计领先 $stones 子（${points.toStringAsFixed(1)} 点）',
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: const Color(0xFF79614A)),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}
