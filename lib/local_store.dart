import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'game.dart';

const modelAsset = 'kata1-b6c96-s175395328-d26788732.txt.gz';
const configAsset = 'mobile.cfg';

class LocalStore {
  LocalStore(this.directory);

  final Directory directory;

  File get _saveFile => File('${directory.path}/game.json');

  static Future<LocalStore> open() async {
    const channel = MethodChannel('app.weiqi/files');
    final path = await channel.invokeMethod<String>('directory');
    if (path == null) {
      throw StateError('Android did not return the files directory');
    }
    return LocalStore(Directory(path));
  }

  Future<({String model, String config})> prepareEngine() async {
    final engineDirectory = await Directory('${directory.path}/engine')
        .create();
    final model = File('${engineDirectory.path}/$modelAsset');
    final config = File('${engineDirectory.path}/$configAsset');
    const modelLength = 4967720;

    if (!await model.exists() || await model.length() != modelLength) {
      final bytes = await rootBundle.load('assets/engine/$modelAsset');
      await _replace(
        model,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }

    final bytes = await rootBundle.load('assets/engine/$configAsset');
    await _replace(
      config,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return (model: model.path, config: config.path);
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
