import 'dart:typed_data';

class DriverDocPickedFile {
  const DriverDocPickedFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

Future<DriverDocPickedFile?> pickDriverDocFileWeb() async => null;
