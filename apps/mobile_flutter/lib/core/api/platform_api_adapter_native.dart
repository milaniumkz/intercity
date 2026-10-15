import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

void configurePlatformApiAdapter(Dio dio) {
  if (Platform.isIOS) {
    // Use Apple's URLSession DNS, proxy and VPN handling on iOS.
    dio.httpClientAdapter = CupertinoAdapter(
      URLSessionConfiguration.ephemeralSessionConfiguration(),
    );
  }
}

Dio? createPlatformLoginFallback() {
  if (!Platform.isIOS) return null;
  return Dio()..httpClientAdapter = IOHttpClientAdapter();
}
