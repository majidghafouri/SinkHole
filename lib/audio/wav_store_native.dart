import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Directory holding the synthesised sounds, under the OS temp directory.
///
/// The app writes them once at startup and never cleans up, which is fine for
/// a handful of short clips and keeps every replay to a single call.
Future<Directory> _soundDirectory() async {
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}/sinkhole_audio');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

/// Native implementation: writes the WAV to a real file with a `.wav`
/// extension.
///
/// Both halves matter. iOS cannot play in-memory bytes at all, and even a file
/// without the extension is rejected by AVPlayer as an unknown format.
Future<Source> wavSource(String name, Uint8List bytes) async {
  final dir = await _soundDirectory();
  final file = File('${dir.path}/$name.wav');
  if (!file.existsSync() || file.lengthSync() != bytes.length) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return DeviceFileSource(file.path);
}
