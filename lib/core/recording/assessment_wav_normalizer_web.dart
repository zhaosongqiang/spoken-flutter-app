import 'dart:typed_data';

import 'wav_pcm16.dart';

Future<Uint8List> normalize(Uint8List bytes) async {
  final formatted = normalizePcm16Wav(
    bytes,
    targetSampleRate: 16000,
    targetChannels: 1,
  );
  return normalizePcm16WavLoudness(formatted);
}
