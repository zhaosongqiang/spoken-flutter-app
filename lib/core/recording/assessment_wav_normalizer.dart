import 'dart:typed_data';

import 'assessment_wav_normalizer_stub.dart'
    if (dart.library.html) 'assessment_wav_normalizer_web.dart'
    as implementation;

Future<Uint8List> normalizeAssessmentWav(Uint8List bytes) =>
    implementation.normalize(bytes);
