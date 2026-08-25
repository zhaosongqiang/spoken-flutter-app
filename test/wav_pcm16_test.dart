import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/core/recording/assessment_wav_normalizer.dart';
import 'package:ielts_speaking/core/recording/wav_pcm16.dart';

void main() {
  test('normalizes 48kHz PCM16 mono WAV to 16kHz mono', () {
    final input = _createPcm16Wav(
      sampleRate: 48000,
      channels: 1,
      frames: 480,
      sampleFor: (frame, channel) => frame % 100,
    );

    final output = normalizePcm16Wav(
      input,
      targetSampleRate: 16000,
      targetChannels: 1,
    );
    final header = ByteData.sublistView(output);

    expect(_fourCc(output, 0), 'RIFF');
    expect(_fourCc(output, 8), 'WAVE');
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint16(32, Endian.little), 2);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), 320);
    expect(output.length, 44 + 320);
  });

  test('mixes stereo channels into mono while resampling', () {
    final input = _createPcm16Wav(
      sampleRate: 48000,
      channels: 2,
      frames: 48,
      sampleFor: (frame, channel) => channel == 0 ? 12000 : -12000,
    );

    final output = normalizePcm16Wav(
      input,
      targetSampleRate: 16000,
      targetChannels: 1,
    );
    final bytes = ByteData.sublistView(output);

    expect(bytes.getUint16(22, Endian.little), 1);
    for (var offset = 44; offset < output.length; offset += 2) {
      expect(bytes.getInt16(offset, Endian.little), 0);
    }
  });

  test('keeps an existing 16kHz PCM16 mono WAV unchanged', () {
    final input = _createPcm16Wav(
      sampleRate: 16000,
      channels: 1,
      frames: 16,
      sampleFor: (frame, channel) => frame,
    );

    final output = normalizePcm16Wav(
      input,
      targetSampleRate: 16000,
      targetChannels: 1,
    );

    expect(identical(output, input), isTrue);
  });

  test('recording entrypoint normalizes format and quiet speech', () async {
    final input = _createPcm16Wav(
      sampleRate: 48000,
      channels: 1,
      frames: 480,
      sampleFor: (frame, channel) => frame.isEven ? 1000 : -1000,
    );

    final output = await normalizeAssessmentWav(input);
    final header = ByteData.sublistView(output);

    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getInt16(44, Endian.little).abs(), greaterThan(1000));
  });

  test('loudness normalization ignores silence around quiet active speech', () {
    final input = _createPcm16Wav(
      sampleRate: 16000,
      channels: 1,
      frames: 1600,
      sampleFor: (frame, channel) {
        if (frame < 320 || frame >= 1280) return 0;
        return frame.isEven ? 1000 : -1000;
      },
    );

    final output = normalizePcm16WavLoudness(
      input,
      maxGainDb: 24,
    );
    final samples = _samples(output);

    expect(samples.take(320), everyElement(0));
    expect(samples.skip(1280), everyElement(0));
    expect(samples[400].abs(), closeTo(4125, 2));
  });

  test('loudness normalization limits peaks below the clipping ceiling', () {
    final input = _createPcm16Wav(
      sampleRate: 16000,
      channels: 1,
      frames: 1600,
      sampleFor: (frame, channel) {
        if (frame == 800) return 30000;
        return frame.isEven ? 1000 : -1000;
      },
    );

    final output = normalizePcm16WavLoudness(input);
    final outputPeak = _samples(output).map((sample) => sample.abs()).reduce(
          (left, right) => left > right ? left : right,
        );

    expect(outputPeak, lessThanOrEqualTo(29205));
    expect(outputPeak, greaterThan(29000));
  });

  test('loudness normalization does not amplify content below the noise gate',
      () {
    final input = _createPcm16Wav(
      sampleRate: 16000,
      channels: 1,
      frames: 320,
      sampleFor: (frame, channel) => frame.isEven ? 50 : -50,
    );

    final output = normalizePcm16WavLoudness(input);

    expect(identical(output, input), isTrue);
  });
}

List<int> _samples(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  return <int>[
    for (var offset = 44; offset < wav.length; offset += 2)
      view.getInt16(offset, Endian.little),
  ];
}

Uint8List _createPcm16Wav({
  required int sampleRate,
  required int channels,
  required int frames,
  required int Function(int frame, int channel) sampleFor,
}) {
  final blockAlign = channels * 2;
  final dataLength = frames * blockAlign;
  final output = Uint8List(44 + dataLength);
  final view = ByteData.sublistView(output);
  _writeFourCc(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataLength, Endian.little);
  _writeFourCc(view, 8, 'WAVE');
  _writeFourCc(view, 12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * blockAlign, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, 16, Endian.little);
  _writeFourCc(view, 36, 'data');
  view.setUint32(40, dataLength, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    for (var channel = 0; channel < channels; channel++) {
      view.setInt16(
        44 + frame * blockAlign + channel * 2,
        sampleFor(frame, channel),
        Endian.little,
      );
    }
  }
  return output;
}

String _fourCc(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

void _writeFourCc(ByteData view, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    view.setUint8(offset + index, value.codeUnitAt(index));
  }
}
