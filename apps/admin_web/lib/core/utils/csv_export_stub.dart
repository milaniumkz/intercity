import 'package:flutter/services.dart';

Future<bool> exportCsv(String csv, {required String filename}) async {
  await Clipboard.setData(ClipboardData(text: csv));
  return false;
}
