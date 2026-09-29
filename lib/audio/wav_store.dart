import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'wav_store_stub.dart' if (dart.library.io) 'wav_store_native.dart' as impl;

/// Turns synthesised WAV bytes into something the platform can play.
///
/// The two platforms disagree here, and the difference matters:
///
///  * iOS cannot play bytes at all. The plugin's `setSourceBytes` is explicitly
///    unimplemented on Darwin, and a file without a recognisable extension is
///    rejected by AVPlayer, so the bytes have to be written to a real `.wav`
///    file first.
///  * The web has no filesystem, and the plugin turns bytes into a data URI
///    there, which works as long as the MIME type is declared.
///
/// [name] must be a stable, filesystem-safe identifier; the file is written once
/// and then replayed for the life of the app.
Future<Source> wavSource(String name, Uint8List bytes) => impl.wavSource(name, bytes);
