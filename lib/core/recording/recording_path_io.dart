import 'dart:io';

Future<String> nextPath() async =>
    '${Directory.systemTemp.path}/ielts-${DateTime.now().microsecondsSinceEpoch}.wav';
