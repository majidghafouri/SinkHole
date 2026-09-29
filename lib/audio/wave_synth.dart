import 'dart:math' as math;
import 'dart:typed_data';

/// Builds 16-bit mono PCM WAV bytes in memory.
///
/// The game ships no audio assets. Every sound is synthesised here at startup,
/// which keeps the download tiny and, more usefully, makes the "next note of a
/// scale" streak melody a matter of arithmetic rather than a recording session.
class WaveSynth {
  const WaveSynth({this.sampleRate = 22050});

  final int sampleRate;

  static const int _headerBytes = 44;

  /// Renders one short tone.
  ///
  /// [partials] are (frequency multiplier, amplitude) pairs mixed together,
  /// which is how the bell-like and buzzy sounds are built from a sine.
  Uint8List tone({
    required double frequency,
    required double milliseconds,
    double gain = 0.5,
    double attackMs = 4,
    double releaseMs = 40,
    List<(double, double)> partials = const [(1.0, 1.0)],
    double vibratoHz = 0,
    double vibratoCents = 0,
    double bendRatio = 1.0,
  }) {
    final frames = (sampleRate * milliseconds / 1000).round();
    final attack = math.max(1, (sampleRate * attackMs / 1000).round());
    final release = math.max(1, (sampleRate * releaseMs / 1000).round());
    final out = Float64List(frames);

    for (var i = 0; i < frames; i++) {
      final t = i / sampleRate;
      final progress = i / frames;

      // A small pitch bend at the start makes hits feel percussive.
      final bend = progress < 0.12 ? 1 + (bendRatio - 1) * (1 - progress / 0.12) : 1.0;
      final vibrato = vibratoCents == 0
          ? 1.0
          : math
                .pow(2, (vibratoCents / 1200) * math.sin(2 * math.pi * vibratoHz * t))
                .toDouble();

      final freq = frequency * bend * vibrato;
      var sample = 0.0;
      for (final (multiplier, amplitude) in partials) {
        sample += amplitude * math.sin(2 * math.pi * freq * multiplier * t);
      }

      // Envelope: fast attack, exponential decay, then a guaranteed fade-out so
      // the tail never clicks.
      final attackGain = i < attack ? i / attack : 1.0;
      final decay = math.exp(-3.2 * progress);
      final fadeOut = i > frames - release ? (frames - i) / release : 1.0;
      out[i] = sample * attackGain * decay * fadeOut;
    }

    return _wrap(out, gain);
  }

  /// Renders a note as a plucked, slightly detuned pair of partials. This is
  /// the timbral signature of the streak melody.
  Uint8List pluck({
    required double frequency,
    required double milliseconds,
    double gain = 0.5,
  }) => tone(
    frequency: frequency,
    milliseconds: milliseconds,
    gain: gain,
    attackMs: 3,
    releaseMs: 60,
    bendRatio: 1.008,
    partials: const [(1.0, 1.0), (2.0, 0.28), (3.01, 0.12)],
  );

  /// Renders a two-note "bwoop" for a wrong answer: a falling interval with a
  /// rounded, non-punishing timbre.
  Uint8List boop({
    double fromHz = 320,
    double toHz = 190,
    required double milliseconds,
    double gain = 0.5,
  }) {
    final frames = (sampleRate * milliseconds / 1000).round();
    final out = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      final progress = i / frames;
      final freq = fromHz + (toHz - fromHz) * progress;
      final env = math.exp(-4.5 * progress);
      out[i] =
          (math.sin(2 * math.pi * freq * i / sampleRate) +
              0.3 * math.sin(4 * math.pi * freq * i / sampleRate)) *
          env;
    }
    return _wrap(out, gain);
  }

  /// Renders a rising sweep for a level change.
  Uint8List whoosh({
    required double milliseconds,
    double fromHz = 180,
    double toHz = 900,
    double gain = 0.4,
  }) {
    final frames = (sampleRate * milliseconds / 1000).round();
    final out = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      final progress = i / frames;
      // Exponential sweep reads as a swoop rather than a slide.
      final freq = fromHz * math.pow(toHz / fromHz, progress).toDouble();
      // A little noise gives it air.
      final noise = _hashNoise(i) * 0.35;
      final env = math.sin(math.pi * progress);
      out[i] = (math.sin(2 * math.pi * freq * i / sampleRate) * 0.6 + noise) * env;
    }
    return _wrap(out, gain);
  }

  /// Renders a loopable chord bed.
  ///
  /// The envelope is raised-cosine at both ends and the length is an exact
  /// whole number of note periods, so the loop has no seam and no click.
  Uint8List pad({
    required double rootHz,
    required double milliseconds,
    double gain = 0.18,
    List<double> intervals = const <double>[1.0, 1.5, 2.0],
  }) {
    final frames = (sampleRate * milliseconds / 1000).round();
    final out = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      final progress = i / frames;
      final env = 0.5 - 0.5 * math.cos(2 * math.pi * progress);
      var sample = 0.0;
      for (final interval in intervals) {
        sample += math.sin(2 * math.pi * rootHz * interval * i / sampleRate);
      }
      out[i] = sample / intervals.length * env;
    }
    return _wrap(out, gain);
  }

  /// Concatenates clips into a single buffer, padding to the longest length.
  /// Used to build the multi-note power-up and boss stingers.
  Uint8List sequence(List<Uint8List> clips, {double gapMs = 0}) {
    final gapFrames = (sampleRate * gapMs / 1000).round();
    final total =
        clips.fold<int>(0, (sum, c) => sum + c.length - _headerBytes) +
        gapFrames * (clips.length - 1);
    final merged = Float64List(total);
    var offset = 0;
    for (final clip in clips) {
      final samples = _samplesOf(clip);
      for (var i = 0; i < samples.length && offset + i < total; i++) {
        merged[offset + i] += samples[i];
      }
      offset += samples.length + gapFrames;
    }
    return _wrap(merged, 1.0);
  }

  /// Pads a clip out to [milliseconds] so it can be looped without a gap.
  Uint8List looped(Uint8List clip, double milliseconds) {
    final target = (sampleRate * milliseconds / 1000).round();
    final samples = _samplesOf(clip);
    final out = Float64List(target);
    for (var i = 0; i < target; i++) {
      out[i] = samples[i % samples.length];
    }
    return _wrap(out, 1.0);
  }

  Float64List _samplesOf(Uint8List wav) {
    final bytes = wav.length - _headerBytes;
    return Float64List(bytes ~/ 2)
      ..setAll(0, _asInts(wav).sublist(_headerBytes ~/ 2).map((v) => v / 32768.0));
  }

  static List<int> _asInts(Uint8List bytes) {
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    return List<int>.generate(
      bytes.length ~/ 2,
      (i) => view.getInt16(i * 2, Endian.little),
    );
  }

  /// Scales a float buffer and writes the RIFF/WAV header around it.
  Uint8List _wrap(Float64List samples, double gain) {
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    // Normalise so every sound lands at a similar perceived level, then apply
    // the caller's gain.
    final normalise = peak > 0 ? gain / peak : 0.0;

    final dataBytes = samples.length * 2;
    final out = Uint8List(_headerBytes + dataBytes);
    final view = ByteData.view(out.buffer);

    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        view.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    view.setUint32(4, 36 + dataBytes, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // PCM header size
    view.setUint16(20, 1, Endian.little); // format: PCM
    view.setUint16(22, 1, Endian.little); // channels: mono
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    view.setUint16(32, 2, Endian.little); // block align
    view.setUint16(34, 16, Endian.little); // bits per sample
    writeAscii(36, 'data');
    view.setUint32(40, dataBytes, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * normalise).clamp(-1.0, 1.0);
      view.setInt16(_headerBytes + i * 2, (v * 32767).round(), Endian.little);
    }
    return out;
  }

  /// Cheap deterministic noise, so a whoosh sounds the same every time.
  static double _hashNoise(int i) {
    var x = (i * 1103515245 + 12345) & 0x7FFFFFFF;
    x ^= x >> 13;
    x = (x * 1274126177) & 0x7FFFFFFF;
    return (x / 0x3FFFFFFF) - 1.0;
  }
}
