import 'dart:isolate';
import 'dart:typed_data';

import 'package:batch_image_processor/features/batch_processor/models/isolate_message.dart';
import 'package:batch_image_processor/features/batch_processor/models/process_result.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class BatchProcessorView extends StatefulWidget {
  const BatchProcessorView({super.key});

  @override
  State<BatchProcessorView> createState() => _BatchProcessorViewState();
}

class _BatchProcessorViewState extends State<BatchProcessorView> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _processedImages = [];
  final List<int> _processingImages = [];
  final Map<int, double> _progressMap = {};

  // Isolate and communication ports
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isolateReady = false;
  bool _isPaused = false;
  String _selectedFilter = 'blur';

  @override
  void initState() {
    super.initState();
    _startIsolate();
  }

  @override
  void dispose() {
    _stopIsolate();
    super.dispose();
  }

  // Initialize the long-lived isolate
  Future<void> _startIsolate() async {
    print('Starting isolate...');
    _receivePort = ReceivePort();

    // Create the isolate
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);

    // Set up communication with the isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        // Store the send port for communication with the isolate
        _sendPort = message;
        setState(() {
          _isolateReady = true;
        });
      } else if (message is List<dynamic> && message.length == 2) {
        // Handle results - comes as [Uint8List, int]
        if (message[0] is Uint8List && message[1] is int) {
          setState(() {
            _processedImages.add(message[0] as Uint8List);
            _processingImages.remove(message[1]);
            _progressMap.remove(message[1]);
          });
        }
      } else if (message is List<dynamic> && message.length == 3) {
        // Handle progress - comes as ["progress", imageId, progressValue]
        if (message[0] == "progress" &&
            message[1] is int &&
            message[2] is double) {
          setState(() {
            _progressMap[message[1]] = message[2];
          });
        }
      }
    });
  }

  // Stop the isolate when done
  void _stopIsolate() {
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  // Select images from gallery
  Future<void> _selectImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.clear();
        _selectedImages.addAll(images);
      });
    }
  }

  // Process the selected images
  Future<void> _processImages() async {
    if (!_isolateReady || _selectedImages.isEmpty) return;

    for (int i = 0; i < _selectedImages.length; i++) {
      if (_processingImages.contains(i)) continue;

      final XFile image = _selectedImages[i];
      final Uint8List imageData = await image.readAsBytes();

      // Send the image to the isolate for processing
      _sendPort!.send(["process", imageData, _selectedFilter, i]);

      setState(() {
        _processingImages.add(i);
        _progressMap[i] = 0.0;
      });
    }
  }

  // Pause or resume processing
  void _togglePause() {
    if (_sendPort == null) return;

    setState(() {
      _isPaused = !_isPaused;
    });

    _sendPort!.send({'command': _isPaused ? 'pause' : 'resume'});
  }

  // Cancel all processing
  void _cancelProcessing() {
    if (_sendPort == null) return;

    _sendPort!.send({'command': 'cancel'});

    setState(() {
      _processingImages.clear();
      _progressMap.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Image Processor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Filter selection dropdown
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String>(
              value: _selectedFilter,
              items: [
                DropdownMenuItem(value: 'blur', child: Text('Blur')),
                DropdownMenuItem(value: 'sepia', child: Text('Sepia')),
                DropdownMenuItem(value: 'grayscale', child: Text('Grayscale')),
                DropdownMenuItem(value: 'pixelate', child: Text('Pixelate')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedFilter = value;
                  });
                }
              },
            ),
          ),

          // Control buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,

            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _selectImages,
                  child: const Text('Select Images'),
                ),
                ElevatedButton(
                  onPressed: _isolateReady ? _processImages : null,
                  child: const Text('Process Images'),
                ),
                ElevatedButton(
                  onPressed: _processingImages.isNotEmpty ? _togglePause : null,
                  child: Text(_isPaused ? 'Resume' : 'Pause'),
                ),
                ElevatedButton(
                  onPressed:
                      _processingImages.isNotEmpty ? _cancelProcessing : null,
                  child: const Text('Cancel Processing'),
                ),
              ],
            ),
          ),

          // Processing status
          if (_processingImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    'Processing ${_processingImages.length} images',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8.0),
                  ...(_progressMap.entries.map((entry) {
                    return Column(
                      children: [
                        Text('Image ${entry.key + 1}'),
                        LinearProgressIndicator(value: entry.value),
                        const SizedBox(height: 8.0),
                      ],
                    );
                  }).toList()),
                ],
              ),
            ),

          // Display results
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
              ),
              itemCount: _processedImages.length,

              itemBuilder: (context, index) {
                return Image.memory(_processedImages[index], fit: BoxFit.cover);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Isolate entry point - must be a top-level function
void _isolateEntryPoint(SendPort mainSendPort) {
  // Create a receive port for incoming messages
  final ReceivePort receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  bool isPaused = false;
  final List<List<dynamic>> queue = [];

  // Listen for messages from the main isolate
  receivePort.listen((message) {
    // Messages are sent as lists for simplicity and type safety

    if (message is List<dynamic>) {
      final String type = message[0] as String;

      if (type == "process") {
        final Uint8List imageData = message[1] as Uint8List;
        final String filterId = message[2] as String;
        final int imageId = message[3] as int;

        if (isPaused) {
          // If paused, add to queue
          queue.add(message);
        } else {
          // Otherwise process immediately
          _processImage(imageData, filterId, imageId, mainSendPort);
        }
      } else if (type == "command") {
        final String command = message[1] as String;

        switch (command) {
          case 'pause':
            isPaused = true;
            break;
          case 'resume':
            isPaused = false;
            // Process queued images
            while (!isPaused && queue.isNotEmpty) {
              final List<dynamic> item = queue.removeAt(0);
              final Uint8List imageData = item[1] as Uint8List;
              final String filterId = item[2] as String;
              final int imageId = item[3] as int;
              _processImage(imageData, filterId, imageId, mainSendPort);
            }
            break;
          case 'cancel':
            queue.clear();
            break;
        }
      }
    }
  });
}

// Function to process an image
Future<void> _processImage(
  Uint8List imageData,
  String filterId,
  int imageId,
  SendPort sendPort,
) async {
  try {
    // Decode image
    final img.Image? image = img.decodeImage(imageData);
    if (image == null) return;

    // Apply selected filter with simulated progress updates
    img.Image processedImage;

    switch (filterId) {
      case 'blur':
        //Simulate a slow processs with progress updates
        for (int i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          sendPort.send(["progress", imageId, i / 10]);
        }
        processedImage = img.gaussianBlur(image, radius: 10);

        break;

      case 'grayscale':
        for (int i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          sendPort.send(["progress", imageId, i / 10]);
        }
        processedImage = img.grayscale(image);
        break;

      case 'sepia':
        for (int i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 150));
          sendPort.send(["progress", imageId, i / 10]);
        }
        processedImage = img.sepia(image);
        break;

      case 'pixelate':
        for (int i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
          sendPort.send(["progress", imageId, i / 10]);
        }
        processedImage = img.pixelate(image, size: 8);
        break;
      default:
        processedImage = image;
    }

    // Encode the processed image and send it back
    final Uint8List processedBytes = Uint8List.fromList(
      img.encodeJpg(processedImage),
    );
    sendPort.send([processedBytes, imageId]);
  } catch (e) {
    print('Error processing image: $e');
  }
}
