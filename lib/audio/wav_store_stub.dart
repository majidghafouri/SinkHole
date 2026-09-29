import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Web implementation: no filesystem, so the bytes go straight to the plugin
/// as a data URI. The MIME type is what lets the browser pick a decoder.
Future<Source> wavSource(String name, Uint8List bytes) async =>
    BytesSource(bytes, mimeType: 'audio/wav');
