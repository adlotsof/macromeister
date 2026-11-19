// Runtime permission helper for camera use (barcode scanner, label OCR,
// meal photos). Android needs an explicit CAMERA grant before opening the
// scanner; otherwise mobile_scanner just shows its error builder and the
// user never sees why.
import 'package:permission_handler/permission_handler.dart';

/// Returns true if the camera permission is (now) granted.
Future<bool> ensureCameraPermission() async {
  final status = await Permission.camera.status;
  if (status.isGranted) return true;
  final res = await Permission.camera.request();
  return res.isGranted;
}
