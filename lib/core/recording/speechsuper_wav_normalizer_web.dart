import 'dart:typed_data';

import 'wav_pcm16.dart';

Future<Uint8List> normalize(Uint8List bytes) async =>
    normalizePcm16Wav(bytes, targetSampleRate: 16000, targetChannels: 1);
