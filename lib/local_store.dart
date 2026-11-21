import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'game.dart';

class LocalStore {
  LocalStore(this.directory);

  static const _channel = MethodChannel('app.weiqi/files');
  static const _configAsset = 'mobile.cfg';

  final Directory directory;

  File get _saveFile => File('${directory.path}/game.json');
  String get _enginePath => '${directory.path}/engine';

  static Future<LocalStore> open() async {
    final path = await _channel.invokeMethod<String>('directory');
    if (path == null) {
      throw StateError('Android did not return the files directory');
    }
    return LocalStore(Directory(path));
  }

  Future<String> prepareModel(AiModel model) async {
    await Directory(_enginePath).create();
    final target = File('$_enginePath/${model.asset}');
    if (!await target.exists() || await target.length() != model.assetBytes) {
      final pending = File('${target.path}.tmp');
      await _channel.invokeMethod<void>('copyModel', {
        'asset': model.asset,
        'path': pending.path,
      });
      if (await pending.length() != model.assetBytes) {
        throw const FormatException('Incomplete KataGo model asset');
      }
      await pending.rename(target.path);
    }
    return target.path;
  }

  Future<({String model, String config})> prepareEngine([
    AiModel model = AiModel.b6c96,
  ]) async {
    final modelPath = await prepareModel(model);
    final config = File('$_enginePath/$_configAsset');
    final bytes = await rootBundle.load('assets/engine/$_configAsset');
    await _replace(
      config,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return (model: modelPath, config: config.path);
  }

  Future<GameRecord?> read() async {
    if (!await _saveFile.exists()) return null;
    final data =
        jsonDecode(await _saveFile.readAsString()) as Map<String, dynamic>;
    return GameRecord.fromJson(data);
  }

  Future<void> write(GameRecord game) =>
      _replace(_saveFile, utf8.encode(jsonEncode(game.toJson())));

  Future<void> _replace(File target, List<int> bytes) async {
    final pending = File('${target.path}.tmp');
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(target.path);
  }
}
