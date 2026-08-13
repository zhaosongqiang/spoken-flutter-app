import 'dart:typed_data';

import 'speechsuper_wav_normalizer_stub.dart'
    if (dart.library.html) 'speechsuper_wav_normalizer_web.dart'
    as implementation;

Future<Uint8List> normalizeSpeechSuperWav(Uint8List bytes) =>
    implementation.normalize(bytes);
