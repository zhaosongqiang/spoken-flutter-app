import 'recording_path_stub.dart'
    if (dart.library.io) 'recording_path_io.dart'
    if (dart.library.html) 'recording_path_web.dart' as implementation;

Future<String> nextRecordingPath() => implementation.nextPath();
