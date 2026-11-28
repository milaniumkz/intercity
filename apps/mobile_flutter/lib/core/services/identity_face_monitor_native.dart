import 'dart:io';
import 'package:camera/camera.dart';
import 'identity_face_guide_model.dart';

final identityCameraFormat = Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

// Legacy capture pages can record without starting a second camera stream.
class IdentityFaceMonitor {
  bool get usesCameraStream => false;
  Future<void> start(CameraController camera, void Function(IdentityFaceSample) report) async {
    report(IdentityFaceSample.unavailable);
  }
  Future<void> beforeRecording(CameraController camera) async {}
  void process(CameraImage image) {}
  Future<void> stop() async {}
  Future<void> dispose() async {}
}
