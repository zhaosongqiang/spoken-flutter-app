import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

Future<void> configure(Dio dio) async {
  dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;
}
