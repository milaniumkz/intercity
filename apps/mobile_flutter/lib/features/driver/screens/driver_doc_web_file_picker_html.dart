// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'driver_doc_web_file_picker_stub.dart';

Future<DriverDocPickedFile?> pickDriverDocFileWeb() {
  final completer = Completer<DriverDocPickedFile?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/jpeg,image/png,image/webp,application/pdf'
    ..multiple = false
    ..style.display = 'none';

  html.document.body?.append(input);

  void complete(DriverDocPickedFile? file) {
    if (!completer.isCompleted) {
      completer.complete(file);
    }
    input.remove();
  }

  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onError.first.then((_) => complete(null));
    reader.onLoad.first.then((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        complete(DriverDocPickedFile(
          name: file.name,
          bytes: Uint8List.view(result),
        ));
      } else if (result is Uint8List) {
        complete(DriverDocPickedFile(name: file.name, bytes: result));
      } else {
        complete(null);
      }
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      input.remove();
      return null;
    },
  );
}
