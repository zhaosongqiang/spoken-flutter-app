import 'dart:math' as math;
import 'dart:typed_data';

const _pcmFormat = 1;
const _pcmBitsPerSample = 16;
const _wavHeaderSize = 44;
const _pcmFullScale = 32768.0;

/// Converts a PCM16 WAV to the sample rate and channel count required by
/// the pronunciation assessment API. Downsampling uses area averaging to avoid simply dropping
/// samples and introducing excessive aliasing.
Uint8List normalizePcm16Wav(
  Uint8List bytes, {
  required int targetSampleRate,
  required int targetChannels,
}) {
  if (targetSampleRate <= 0 || targetChannels != 1) {
    throw const FormatException('Unsupported target WAV format');
  }

  final source = _readPcm16Wav(bytes);
  if (source.sampleRate == targetSampleRate &&
      source.channels == targetChannels) {
    return bytes;
  }

  final sourceFrames = source.dataLength ~/ source.blockAlign;
  if (sourceFrames == 0) {
    throw const FormatException('WAV contains no audio frames');
  }
  final targetFrames = math.max(
    1,
    (sourceFrames * targetSampleRate / source.sampleRate).round(),
  );
  final output = Uint8List(_wavHeaderSize + targetFrames * 2);
  final outputView = ByteData.sublistView(output);
  _writeHeader(outputView, targetSampleRate, targetFrames * 2);

  final sourceView = ByteData.sublistView(bytes);
  final sourceStep = sourceFrames / targetFrames;
  for (var frame = 0; frame < targetFrames; frame++) {
    final value = sourceStep >= 1
        ? _downsampleFrame(
            sourceView,
            source,
            frame * sourceStep,
            math.min(sourceFrames.toDouble(), (frame + 1) * sourceStep),
          )
        : _interpolateFrame(
            sourceView,
            source,
            math.min(
              sourceFrames - 1.0,
              (frame + 0.5) * sourceStep - 0.5,
            ),
            sourceFrames,
          );
    outputView.setInt16(
      _wavHeaderSize + frame * 2,
      value.round().clamp(-32768, 32767).toInt(),
      Endian.little,
    );
  }
  return output;
}

/// Normalizes active speech in a PCM16 WAV while preserving headroom.
///
/// RMS is measured only in 20 ms frames above [noiseGateDbfs], so leading and
/// trailing silence do not cause excessive amplification. Gain is capped by
/// [maxGainDb] and by [peakCeilingDbfs], keeping the operation linear and
/// preventing clipping that could affect pronunciation assessment.
Uint8List normalizePcm16WavLoudness(
  Uint8List bytes, {
  double targetRmsDbfs = -18,
  double peakCeilingDbfs = -1,
  double maxGainDb = 12,
  double noiseGateDbfs = -50,
}) {
  if (targetRmsDbfs >= 0) {
    throw ArgumentError.value(targetRmsDbfs, 'targetRmsDbfs', 'must be < 0');
  }
  if (peakCeilingDbfs > 0) {
    throw ArgumentError.value(
      peakCeilingDbfs,
      'peakCeilingDbfs',
      'must be <= 0',
    );
  }
  if (maxGainDb < 0) {
    throw ArgumentError.value(maxGainDb, 'maxGainDb', 'must be >= 0');
  }

  final source = _readPcm16Wav(bytes);
  final sourceFrames = source.dataLength ~/ source.blockAlign;
  if (sourceFrames == 0) {
    throw const FormatException('WAV contains no audio frames');
  }

  final view = ByteData.sublistView(bytes);
  final framesPerWindow = math.max(1, (source.sampleRate * .02).round());
  final gateAmplitude = _dbfsToAmplitude(noiseGateDbfs);
  var activeSquareSum = 0.0;
  var activeSampleCount = 0;
  var peak = 0;

  for (var windowStart = 0;
      windowStart < sourceFrames;
      windowStart += framesPerWindow) {
    final windowEnd = math.min(sourceFrames, windowStart + framesPerWindow);
    var windowSquareSum = 0.0;
    var windowSampleCount = 0;
    for (var frame = windowStart; frame < windowEnd; frame++) {
      final frameOffset = source.dataOffset + frame * source.blockAlign;
      for (var channel = 0; channel < source.channels; channel++) {
        final sample = view.getInt16(
          frameOffset + channel * 2,
          Endian.little,
        );
        peak = math.max(peak, sample.abs());
        windowSquareSum += sample * sample;
        windowSampleCount++;
      }
    }
    final windowRms = math.sqrt(windowSquareSum / windowSampleCount);
    if (windowRms >= gateAmplitude) {
      activeSquareSum += windowSquareSum;
      activeSampleCount += windowSampleCount;
    }
  }

  if (peak == 0 || activeSampleCount == 0) return bytes;

  final activeRms = math.sqrt(activeSquareSum / activeSampleCount);
  final targetGain = _dbfsToAmplitude(targetRmsDbfs) / activeRms;
  final maximumGain = math.pow(10, maxGainDb / 20).toDouble();
  final peakLimitedGain = _dbfsToAmplitude(peakCeilingDbfs) / peak;
  final gain = math.min(targetGain, math.min(maximumGain, peakLimitedGain));
  if ((gain - 1).abs() < .001) return bytes;

  final output = Uint8List.fromList(bytes);
  final outputView = ByteData.sublistView(output);
  for (var frame = 0; frame < sourceFrames; frame++) {
    final frameOffset = source.dataOffset + frame * source.blockAlign;
    for (var channel = 0; channel < source.channels; channel++) {
      final offset = frameOffset + channel * 2;
      final sample = outputView.getInt16(offset, Endian.little);
      outputView.setInt16(
        offset,
        (sample * gain).round().clamp(-32768, 32767).toInt(),
        Endian.little,
      );
    }
  }
  return output;
}

double _dbfsToAmplitude(double dbfs) => _pcmFullScale * math.pow(10, dbfs / 20);

double _downsampleFrame(
  ByteData bytes,
  _Pcm16Wav source,
  double start,
  double end,
) {
  var cursor = start;
  var weightedSum = 0.0;
  var totalWeight = 0.0;
  while (cursor < end) {
    final frame = cursor.floor();
    final boundary = math.min(end, frame + 1.0);
    final weight = boundary - cursor;
    weightedSum += _readMonoFrame(bytes, source, frame) * weight;
    totalWeight += weight;
    cursor = boundary;
  }
  return totalWeight == 0 ? 0 : weightedSum / totalWeight;
}

double _interpolateFrame(
  ByteData bytes,
  _Pcm16Wav source,
  double position,
  int sourceFrames,
) {
  final safePosition = math.max(0.0, position);
  final left = safePosition.floor();
  final right = math.min(sourceFrames - 1, left + 1);
  final fraction = safePosition - left;
  final leftValue = _readMonoFrame(bytes, source, left);
  final rightValue = _readMonoFrame(bytes, source, right);
  return leftValue + (rightValue - leftValue) * fraction;
}

double _readMonoFrame(ByteData bytes, _Pcm16Wav source, int frame) {
  final frameOffset = source.dataOffset + frame * source.blockAlign;
  var sum = 0;
  for (var channel = 0; channel < source.channels; channel++) {
    sum += bytes.getInt16(frameOffset + channel * 2, Endian.little);
  }
  return sum / source.channels;
}

_Pcm16Wav _readPcm16Wav(Uint8List bytes) {
  if (bytes.length < 12 ||
      _fourCc(bytes, 0) != 'RIFF' ||
      _fourCc(bytes, 8) != 'WAVE') {
    throw const FormatException('Invalid WAV container');
  }

  final view = ByteData.sublistView(bytes);
  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? blockAlign;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = _fourCc(bytes, offset);
    final chunkLength = view.getUint32(offset + 4, Endian.little);
    final payloadOffset = offset + 8;
    if (chunkLength > bytes.length - payloadOffset) {
      throw const FormatException('Truncated WAV chunk');
    }
    if (chunkId == 'fmt ' && chunkLength >= 16) {
      audioFormat = view.getUint16(payloadOffset, Endian.little);
      channels = view.getUint16(payloadOffset + 2, Endian.little);
      sampleRate = view.getUint32(payloadOffset + 4, Endian.little);
      blockAlign = view.getUint16(payloadOffset + 12, Endian.little);
      bitsPerSample = view.getUint16(payloadOffset + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = payloadOffset;
      dataLength = chunkLength;
    }
    offset = payloadOffset + chunkLength + (chunkLength.isOdd ? 1 : 0);
  }

  if (audioFormat != _pcmFormat ||
      channels == null ||
      channels <= 0 ||
      sampleRate == null ||
      sampleRate <= 0 ||
      bitsPerSample != _pcmBitsPerSample ||
      blockAlign == null ||
      blockAlign < channels * 2 ||
      dataOffset == null ||
      dataLength == null) {
    throw const FormatException('WAV must contain PCM16 audio');
  }
  return _Pcm16Wav(
    sampleRate: sampleRate,
    channels: channels,
    blockAlign: blockAlign,
    dataOffset: dataOffset,
    dataLength: dataLength,
  );
}

void _writeHeader(ByteData view, int sampleRate, int dataLength) {
  _writeFourCc(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataLength, Endian.little);
  _writeFourCc(view, 8, 'WAVE');
  _writeFourCc(view, 12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, _pcmFormat, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * 2, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, _pcmBitsPerSample, Endian.little);
  _writeFourCc(view, 36, 'data');
  view.setUint32(40, dataLength, Endian.little);
}

String _fourCc(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

void _writeFourCc(ByteData view, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    view.setUint8(offset + index, value.codeUnitAt(index));
  }
}

class _Pcm16Wav {
  const _Pcm16Wav({
    required this.sampleRate,
    required this.channels,
    required this.blockAlign,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final int blockAlign;
  final int dataOffset;
  final int dataLength;
}
