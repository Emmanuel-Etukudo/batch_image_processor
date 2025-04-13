// Result class for processed images
import 'dart:typed_data';

class ProcessResult {
  final Uint8List processedImage;
  final int imageId;

  ProcessResult({required this.processedImage, required this.imageId});
}
