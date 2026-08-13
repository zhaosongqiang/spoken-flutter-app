import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'recording_path.dart';

enum VoiceRecorderStatus { idle, recording, processing }

class RecordedWav {
  const RecordedWav({required this.bytes, required this.duration});

  final Uint8List bytes;
  final Duration duration;
}

class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder({this.maxDuration = const Duration(seconds: 120)});

  final Duration maxDuration;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  VoiceRecorderStatus _status = VoiceRecorderStatus.idle;
  Duration _elapsed = Duration.zero;
  String? _error;
  Future<void> Function()? _onMaximum;

  VoiceRecorderStatus get status => _status;
  Duration get elapsed => _elapsed;
  String? get error => _error;

  Future<void> start({required Future<void> Function() onMaximum}) async {
    if (_status != VoiceRecorderStatus.idle) return;
    _error = null;
    try {
      if (!await _recorder.hasPermission()) {
        throw const VoiceRecorderException('需要麦克风权限才能开始练习');
      }
      final path = await nextRecordingPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: path,
      );
      _status = VoiceRecorderStatus.recording;
      _elapsed = Duration.zero;
      _onMaximum = onMaximum;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _elapsed += const Duration(seconds: 1);
        notifyListeners();
        if (_elapsed >= maxDuration) {
          final callback = _onMaximum;
          _onMaximum = null;
          if (callback != null) unawaited(callback());
        }
      });
      notifyListeners();
    } catch (error) {
      _status = VoiceRecorderStatus.idle;
      _error = _messageFor(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<RecordedWav?> stop() async {
    if (_status != VoiceRecorderStatus.recording) return null;
    _timer?.cancel();
    _onMaximum = null;
    _status = VoiceRecorderStatus.processing;
    notifyListeners();
    final duration = _elapsed;
    try {
      final outputPath = await _recorder.stop();
      if (outputPath == null || outputPath.isEmpty) {
        throw const VoiceRecorderException('没有检测到有效录音，请重试');
      }
      final bytes = await XFile(outputPath).readAsBytes();
      if (!_looksLikeWav(bytes)) {
        throw const VoiceRecorderException('录音格式无效，请重试');
      }
      return RecordedWav(bytes: bytes, duration: duration);
    } catch (error) {
      _error = _messageFor(error);
      rethrow;
    } finally {
      _status = VoiceRecorderStatus.idle;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    _timer?.cancel();
    _onMaximum = null;
    if (_status != VoiceRecorderStatus.idle) await _recorder.cancel();
    _status = VoiceRecorderStatus.idle;
    _elapsed = Duration.zero;
    notifyListeners();
  }

  bool _looksLikeWav(Uint8List bytes) =>
      bytes.length > 44 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WAVE';

  String _messageFor(Object error) {
    if (error is VoiceRecorderException) return error.message;
    final text = error.toString().toLowerCase();
    if (text.contains('permission')) return '麦克风权限未开启，请在系统设置中允许访问';
    if (text.contains('notfound') || text.contains('device')) {
      return '没有找到可用的麦克风';
    }
    return '录音启动失败，请检查麦克风后重试';
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.message);

  final String message;

  @override
  String toString() => message;
}
