import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class AppAudioService {
  final AudioPlayer _player = AudioPlayer();
  String? _activeKey;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  String? get activeKey => _activeKey;

  Future<void> toggleUrl(String key, String url) async {
    if (url.isEmpty) throw StateError('音频地址为空');
    if (_activeKey == key && _player.playing) {
      await stop();
      return;
    }
    await _player.stop();
    _activeKey = key;
    await _player.setUrl(url);
    await _player.play();
  }

  Future<void> playBytes(String key, Uint8List bytes,
      {String? contentType}) async {
    await _player.stop();
    _activeKey = key;
    await _player.setAudioSource(
      _BytesAudioSource(bytes, contentType ?? 'audio/mpeg'),
    );
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    _activeKey = null;
  }

  Future<void> dispose() => _player.dispose();
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
