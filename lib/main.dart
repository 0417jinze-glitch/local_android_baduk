import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'game.dart';
import 'game_controller.dart';
import 'go_board.dart';

const _paper = Color(0xFFF8F5EC);
const _forest = Color(0xFF264C3B);
const _ink = Color(0xFF24382F);
const _quiet = Color(0xFF5C685D);
const _border = Color(0xFFDCDDD0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerLicenses();
  runApp(const WeiqiApp());
}

void _registerLicenses() {
  const licenses = {
    'KataGo': 'KataGo',
    'KataGo 贡献者': 'KataGo-contributors',
    'KataGo 模型': 'KataGo-model',
    'Eigen': 'Eigen',
    'ghc::filesystem': 'ghc-filesystem',
    'half': 'half',
    'nlohmann/json': 'nlohmann-json',
    'SHA2': 'SHA2',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in licenses.entries) {
      final text = await rootBundle.loadString(
        'assets/licenses/${entry.value}.txt',
      );
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}

class WeiqiApp extends StatelessWidget {
  const WeiqiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '离线围棋',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _forest, surface: _paper),
        scaffoldBackgroundColor: _paper,
        appBarTheme: const AppBarTheme(
          backgroundColor: _paper,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const _GameScreen(),
    );
  }
}

class _GameScreen extends StatefulWidget {
  const _GameScreen();

  @override
  State<_GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<_GameScreen> {
  final _game = GameController();

  @override
  void initState() {
    super.initState();
    unawaited(_game.load());
  }

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  Future<void> _newGame() async {
    final settings = await showModalBottomSheet<GameRecord>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _NewGameSheet(record: _game.record),
    );
    if (!mounted || settings == null) return;
    await _game.startGame(settings.size, settings.human, settings.difficulty);
  }

  Future<void> _restart() async {
    final record = _game.record;
    if (record.moves.isNotEmpty && record.result == null) {
      final confirmed = await _confirm('重开对局？', '当前棋谱将被替换。', '重开');
      if (!mounted || !confirmed) return;
    }
    await _game.startGame(record.size, record.human, record.difficulty);
  }

  Future<void> _resign() async {
    final confirmed = await _confirm('确认认输？', '对局将结束，KataGo 获胜。', '认输');
    if (mounted && confirmed) await _game.resign();
  }

  Future<bool> _confirm(String title, String message, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _game,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text(
            '离线围棋',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _game.ready && !_game.busy ? _newGame : null,
              icon: const Icon(Icons.add, size: 19),
              label: const Text('新对局'),
            ),
            IconButton(
              tooltip: '开源许可',
              onPressed: () =>
                  showLicensePage(context: context, applicationName: '离线围棋'),
              icon: const Icon(Icons.info_outline, size: 21),
            ),
            const SizedBox(width: 5),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _game.ready ? _buildGame() : _buildLoading(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_game.busy) const CircularProgressIndicator(),
          if (_game.busy) const SizedBox(height: 18),
          Text(_game.notice ?? '正在加载本地引擎…'),
          if (!_game.busy)
            TextButton(onPressed: _game.load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildGame() {
    final record = _game.record;
    final position = _game.position!;
    final last = record.moves.lastOrNull;
    final lastText = last == null
        ? '第 0 手'
        : last == pass
        ? '第 ${record.moves.length} 手 · 停一手'
        : '第 ${record.moves.length} 手';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(game: _game),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${record.size} × ${record.size}',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(lastText, style: const TextStyle(color: _quiet)),
                ],
              ),
              const SizedBox(height: 5),
              GoBoard(
                key: const ValueKey('board'),
                position: position,
                lastPoint: last == pass ? null : last,
                selectedPoint: _game.selectedPoint,
                onSelect: _game.canPlay ? _game.selectPoint : null,
              ),
              const SizedBox(height: 6),
              _PlacementControls(game: _game),
              if (_game.notice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            notice,
                            style: const TextStyle(color: Color(0xFF874625)),
                          ),
                        ),
                      ),
                      if (_game.canRetrySearch)
                        TextButton(
                          onPressed: _game.retrySearch,
                          child: const Text('重试'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Text(
                    'AI 难度',
                    style: TextStyle(
                      color: _quiet,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<Difficulty>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: [
                        for (final level in Difficulty.values)
                          ButtonSegment(value: level, label: Text(level.label)),
                      ],
                      selected: {record.difficulty},
                      onSelectionChanged: _game.busy
                          ? null
                          : (levels) =>
                                unawaited(_game.setDifficulty(levels.single)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _game.canPlay ? () => _game.play(pass) : null,
                    icon: const Icon(Icons.skip_next_outlined, size: 18),
                    label: const Text('停一手'),
                  ),
                  OutlinedButton(
                    onPressed: _game.canUndo ? _game.undo : null,
                    child: const Text('悔棋'),
                  ),
                  OutlinedButton(
                    onPressed: _game.busy ? null : _restart,
                    child: const Text('重开'),
                  ),
                  TextButton(
                    onPressed: _game.busy || record.result != null
                        ? null
                        : _resign,
                    child: const Text('认输'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '中国规则（OGS） · 白贴 7.5 点',
                textAlign: TextAlign.center,
                style: TextStyle(color: _quiet, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementControls extends StatelessWidget {
  const _PlacementControls({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final position = game.position!;
    final point = game.selectedPoint;
    final occupied = point != null && position.stones[point] != 0;
    final label = point == null
        ? (game.canPlay ? '点选交叉点' : '')
        : '预选 ${boardCoordinate(position.size, point)}${occupied ? ' · 已有棋子' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            Wrap(
              children: [
                for (final (icon, tooltip, dx, dy) in const [
                  (Icons.arrow_back, '向左', -1, 0),
                  (Icons.arrow_upward, '向上', 0, -1),
                  (Icons.arrow_downward, '向下', 0, 1),
                  (Icons.arrow_forward, '向右', 1, 0),
                ])
                  IconButton(
                    tooltip: tooltip,
                    onPressed: game.selectionNeighbor(dx, dy) == null
                        ? null
                        : () => game.shiftSelection(dx, dy),
                    icon: Icon(icon),
                  ),
              ],
            ),
            FilledButton(
              onPressed: game.canConfirmSelection
                  ? game.confirmSelection
                  : null,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
              child: const Text('确认落子'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  label,
                  style: TextStyle(
                    color: occupied ? const Color(0xFF874625) : _quiet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: game.canPlay && point != null
                  ? () => game.selectPoint(null)
                  : null,
              child: const Text('取消选点'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final record = game.record;
    final position = game.position!;
    final result = record.result;
    final status = result == null ? _turnLabel() : _resultLabel(result);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1E6),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            spacing: 10,
            children: [
              _PlayerLabel('你', record.human),
              _PlayerLabel('KataGo', record.human.opponent),
            ],
          ),
          const SizedBox(height: 9),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                if (game.searching) ...[
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: _forest,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
                if (result == null) ...[
                  const SizedBox(width: 9),
                  Text(
                    '${position.next.label}棋行棋',
                    style: const TextStyle(color: _quiet, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _turnLabel() {
    if (game.searching) return 'AI 思考中';
    if (game.canPlay) return '你的回合';
    if (game.busy) return '正在更新棋局';
    return 'AI 回合';
  }

  String _resultLabel(GameResult result) {
    final winner = result.winner;
    if (winner == null) return '和棋';
    if (result.kind == ResultKind.resignation) return '${winner.label}胜 · 对手认输';
    return '${winner.label}胜 ${result.margin!.toStringAsFixed(1)} 点';
  }
}

class _PlayerLabel extends StatelessWidget {
  const _PlayerLabel(this.name, this.color);

  final String name;
  final Stone color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color == Stone.black
                ? const Color(0xFF252924)
                : const Color(0xFFFFFDF4),
            border: Border.all(color: const Color(0xFF626A5E)),
          ),
        ),
        const SizedBox(width: 6),
        Text('$name · 执${color.label}', style: const TextStyle(color: _quiet)),
      ],
    );
  }
}

class _NewGameSheet extends StatefulWidget {
  const _NewGameSheet({required this.record});

  final GameRecord record;

  @override
  State<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends State<_NewGameSheet> {
  late int _size = widget.record.size;
  late Stone _human = widget.record.human;
  late Difficulty _difficulty = widget.record.difficulty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '新对局',
              style: TextStyle(
                color: _ink,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.record.moves.isNotEmpty ||
                widget.record.result != null) ...[
              const SizedBox(height: 4),
              const Text('开始后将替换当前棋局。', style: TextStyle(color: _quiet)),
            ],
            _choices(
              '棋盘',
              boardSizes,
              _size,
              (size) => '$size × $size',
              (size) => setState(() => _size = size),
            ),
            _choices(
              '执子',
              Stone.values,
              _human,
              (stone) => '执${stone.label}',
              (stone) => setState(() => _human = stone),
            ),
            _choices(
              'AI 难度',
              Difficulty.values,
              _difficulty,
              (level) => level.label,
              (level) => setState(() => _difficulty = level),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                GameRecord(size: _size, human: _human, difficulty: _difficulty),
              ),
              child: const Text('开始对弈'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choices<T>(
    String name,
    List<T> values,
    T selected,
    String Function(T) label,
    ValueChanged<T> onSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(color: _quiet, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final value in values)
                ChoiceChip(
                  label: Text(label(value)),
                  selected: value == selected,
                  onSelected: (_) => onSelected(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
