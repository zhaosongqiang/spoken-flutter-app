import 'package:dio/dio.dart';

import 'http_platform_stub.dart'
    if (dart.library.io) 'http_platform_io.dart'
    if (dart.library.html) 'http_platform_web.dart' as implementation;

Future<void> configurePlatformHttp(Dio dio) => implementation.configure(dio);
