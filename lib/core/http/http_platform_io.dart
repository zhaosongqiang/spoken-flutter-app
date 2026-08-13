import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<void> configure(Dio dio) async {
  final supportDirectory = await getApplicationSupportDirectory();
  final cookieJar = PersistCookieJar(
    storage: FileStorage(path.join(supportDirectory.path, '.cookies')),
  );
  dio.interceptors.add(CookieManager(cookieJar));
}
