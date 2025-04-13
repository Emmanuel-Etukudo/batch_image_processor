// Message class for communication between isolates
import 'dart:typed_data';

class IsolateMessage {
  final Uint8List imageData;
  final String filterId;
  final int imageId;

  IsolateMessage({
    required this.imageData,
    required this.filterId,
    required this.imageId,
  });
}
