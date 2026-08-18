import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class AppAudioService {
  AppAudioService() {
    _completionSubscription = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _activeKey = null;
    });
  }

  final AudioPlayer _player = AudioPlayer();
  String? _activeKey;
  int _operationId = 0;
  late final StreamSubscription<ProcessingState> _completionSubscription;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  String? get activeKey => _activeKey;

  Future<void> toggleUrl(String key, String url) async {
    if (url.isEmpty) throw StateError('音频地址为空');
    if (_activeKey == key &&
        _player.playing &&
        _player.processingState != ProcessingState.completed) {
      await stop();
      return;
    }
    await playUrl(key, url);
  }

  Future<void> playUrl(String key, String url) async {
    if (url.isEmpty) throw StateError('音频地址为空');
    final operationId = ++_operationId;
    await _player.stop();
    if (operationId != _operationId) return;
    _activeKey = key;
    await _player.setUrl(url);
    if (operationId != _operationId) return;
    await _player.play();
  }

  Future<void> playBytes(String key, Uint8List bytes,
      {String? contentType}) async {
    final operationId = ++_operationId;
    await _player.stop();
    if (operationId != _operationId) return;
    _activeKey = key;
    await _player.setAudioSource(
      _BytesAudioSource(bytes, contentType ?? 'audio/mpeg'),
    );
    if (operationId != _operationId) return;
    await _player.play();
  }

  Future<void> stop() async {
    _operationId++;
    _activeKey = null;
    await _player.stop();
  }

  Future<void> dispose() async {
    _operationId++;
    _activeKey = null;
    await _completionSubscription.cancel();
    await _player.dispose();
  }
}

// just_audio currently exposes in-memory playback through this experimental API.
// ignore: experimental_member_use
class _BytesAudioSource extends StreamAudioSource {
  _BytesAudioSource(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final offset = start ?? 0;
    final last = end ?? bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: last - offset,
      offset: offset,
      stream: Stream<List<int>>.value(bytes.sublist(offset, last)),
      contentType: contentType,
    );
  }
}
