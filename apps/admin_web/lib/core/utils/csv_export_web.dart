import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> exportCsv(String csv, {required String filename}) async {
  final blob = web.Blob([utf8.encode('\uFEFF$csv').toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.append(link);
  try {
    link.click();
  } finally {
    link.remove();
    Future<void>.delayed(
        const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  }
  return true;
}
