import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; // <-- Inimport ang Face Detection
import 'package:image_picker/image_picker.dart';
import 'package:your_project_name/utils/faceclassifier.dart';

class IdCardOcrScreen extends StatefulWidget {
  const IdCardOcrScreen({super.key});

  // ... (Inimbak ang iyong parseIdCardFields, _extractValueFromLineOrNext, _cleanNameValue, at _extractNameValue dito nang walang bago)
  static Map<String, String> parseIdCardFields(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    String firstName = '';
    String middleName = '';
    String lastName = '';
    String idNumber = '';
    final idRegex = RegExp(
      r'(?:LICENSE|LICENCE|ID|PHILSYS|DRIVER|DRIVERS|CARD|CRN)(?:\s+(?:NO|NUMBER))?[\s:#-]*([A-Z0-9]{2,}(?:[-/][A-Z0-9]{2,})*)',
      caseSensitive: false,
    );
    final idMatch = idRegex.firstMatch(rawText);
    if (idMatch != null) idNumber = idMatch.group(1)?.trim() ?? '';
    for (int i = 0; i < lines.length; i++) {
      final currentLine = lines[i].toUpperCase();
      if (lastName.isEmpty &&
          (currentLine.contains('LAST NAME') ||
              currentLine.contains('SURNAME') ||
              currentLine.contains('FAMILY NAME'))) {
        lastName = _extractValueFromLineOrNext(
          lines,
          i,
          r'(?:LAST|SURNAME|FAMILY)\s+NAME[\s:#-]*([A-Z\s]+)',
        );
      }
      if (firstName.isEmpty &&
          (currentLine.contains('FIRST NAME') ||
              currentLine.contains('GIVEN NAME'))) {
        firstName = _extractValueFromLineOrNext(
          lines,
          i,
          r'(?:FIRST|GIVEN)\s+NAME[\s:#-]*([A-Z0-9\s\.-]+)',
        );
      }
      if (middleName.isEmpty && currentLine.contains('MIDDLE NAME')) {
        middleName = _extractValueFromLineOrNext(
          lines,
          i,
          r'MIDDLE\s+NAME[\s:#-]*([A-Z0-9\s\.-]+)',
        );
      }
    }
    if (firstName.isEmpty || lastName.isEmpty) {
      final cleanLines = lines.where((line) {
        final upper = line.toUpperCase();
        return !upper.contains('REPUBLIC') &&
            !upper.contains('PHILIPPINES') &&
            !upper.contains('OFFICE') &&
            !upper.contains('IDENTITY') &&
            !upper.contains('AUTHORITY') &&
            !upper.contains('COMMISSION') &&
            !upper.contains('TRANSPORTATION') &&
            !upper.contains('DRIVER');
      }).toList();
      if (cleanLines.isNotEmpty && firstName.isEmpty) {
        for (var line in cleanLines) {
          final clean = _cleanNameValue(line);
          if (clean.length > 2) {
            if (lastName.isEmpty) {
              lastName = clean;
            } else if (firstName.isEmpty) {
              firstName = clean;
              break;
            }
          }
        }
      }
    }
    return {
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'idNumber': idNumber,
    };
  }

  static String _extractValueFromLineOrNext(
    List<String> lines,
    int currentIndex,
    String regexPattern,
  ) {
    final currentLine = lines[currentIndex];
    final match = RegExp(
      regexPattern,
      caseSensitive: false,
    ).firstMatch(currentLine);
    if (match != null && match.group(1) != null) {
      final candidate = _cleanNameValue(match.group(1)!);
      if (candidate.length > 1) return candidate;
    }
    if (currentIndex + 1 < lines.length) {
      final nextLine = lines[currentIndex + 1];
      final upperNext = nextLine.toUpperCase();
      if (!upperNext.contains('NAME') &&
          !upperNext.contains('DATE') &&
          !upperNext.contains('REPUBLIC') &&
          upperNext.trim().length > 1) {
        return _cleanNameValue(nextLine);
      }
    }
    return '';
  }

  static String _cleanNameValue(String value) {
    return value
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z\s-]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  static String? _extractNameValue(String line) {
    if (line.contains('REPUBLIC') ||
        line.contains('PHILIPPINES') ||
        line.contains('DRIVER') ||
        line.contains('LICENSE') ||
        line.contains('LICENCE') ||
        line.contains('PHILSYS'))
      return null;
    final nameMatch = RegExp(r'NAME[\s:#-]*([A-Z0-9\s]+)').firstMatch(line);
    if (nameMatch != null) {
      final value = _cleanNameValue(nameMatch.group(1)!);
      if (value.isNotEmpty && value != 'NAME') return value;
    }
    final fallbackMatch = RegExp(
      r'([A-Z]{2,}(?:\s+[A-Z0-9]{2,}){1,2})',
    ).firstMatch(line);
    if (fallbackMatch != null) {
      final value = _cleanNameValue(fallbackMatch.group(1)!);
      if (value.isNotEmpty && value != 'NAME') return value;
    }
    return null;
  }

  @override
  State<IdCardOcrScreen> createState() => _IdCardOcrScreenState();
}

class _IdCardOcrScreenState extends State<IdCardOcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();

  final FaceClassifier _faceClassifier = FaceClassifier();
  List<Face> _idFaces = [];

  // Gagawa ng Face Detector instance
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  File? _idImageFile;
  File? _selfieImageFile; // <-- Lalagyan ng Selfie photo

  String _firstName = '';
  String _middleName = '';
  String _lastName = '';
  String _idNumber = '';

  bool _isLoading = false;
  String _verificationStatus =
      ''; // <-- Status ng Face Matching (e.g., "Matched!", "Failed")
  bool _idHasFace = false;
  bool _selfieHasFace = false;

  // Kumuha ng Larawan para sa ID
  Future<void> _pickIdImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (pickedFile == null) return;

      setState(() {
        _idImageFile = File(pickedFile.path);
        _selfieImageFile = null; // Reset selfie kapag nagpalit ng ID
        _verificationStatus = '';
        _isLoading = true;
      });

      // 1. Patakbuhin ang OCR Text Recognition
      await _recognizeText(_idImageFile!);

      // 2. Patakbuhin ang Face Detection sa ID Card
      await _detectFaceOnId(_idImageFile!);
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Kumuha ng Larawan para sa Selfie
  Future<void> _idCaptureSelfie() async {
    if (_idImageFile == null) {
      _showSnackBar('Kunan muna ng larawan ang ID bago mag-selfie.');
      return;
    }

    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera, // Laging camera kapag selfie
        preferredCameraDevice: CameraDevice.front, // Buksan ang front camera
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      setState(() {
        _selfieImageFile = File(pickedFile.path);
        _isLoading = true;
        _verificationStatus = 'Verifying face...';
      });

      // Patakbuhin ang Face Verification
      await _verifyFaceMatch();
    } catch (e) {
      _showSnackBar('Selfie error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _recognizeText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    final rawText = recognizedText.text.trim();
    final parsedFields = IdCardOcrScreen.parseIdCardFields(rawText);

    setState(() {
      _firstName = parsedFields['firstName'] ?? '';
      _middleName = parsedFields['middleName'] ?? '';
      _lastName = parsedFields['lastName'] ?? '';
      _idNumber = parsedFields['idNumber'] ?? '';
    });
  }

  @override
  void initState() {
    super.initState();
    _faceClassifier.loadModel();
  }

  // Pag-detect kung may mukha sa loob ng ID Card
  Future<void> _detectFaceOnId(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final faces = await _faceDetector.processImage(inputImage);

    setState(() {
      _idFaces = faces;
      _idHasFace = faces.isNotEmpty;
    });

    if (!_idHasFace) {
      _showSnackBar(
        'Babala: Walang mukha na ma-detect sa ID card. Siguraduhing malinaw ang pagkakuha.',
      );
    }
  }

  // Pagkumpara ng Mukha sa ID at Mukha sa Selfie
  Future<void> _verifyFaceMatch() async {
    if (_idImageFile == null || _selfieImageFile == null) return;

    final selfieInputImage = InputImage.fromFile(_selfieImageFile!);
    final selfieFaces = await _faceDetector.processImage(selfieInputImage);

    setState(() {
      _selfieHasFace = selfieFaces.isNotEmpty;
    });

    if (!_selfieHasFace) {
      setState(
        () => _verificationStatus =
            'Verification Failed: No face detected in selfie.',
      );
      return;
    }

    if (!_idHasFace || _idFaces.isEmpty) {
      setState(
        () => _verificationStatus =
            'Verification Failed: Cannot match because ID has no clear face.',
      );
      return;
    }

    final croppedIdFace = _faceClassifier.cropFace(_idImageFile!, _idFaces.first);
    final croppedSelfieFace = _faceClassifier.cropFace(_selfieImageFile!, selfieFaces.first);

    if (croppedIdFace == null || croppedSelfieFace == null) {
      setState(
        () => _verificationStatus =
            'Verification Failed: Image processing error.',
      );
      return;
    }

    final idEmbeddings = _faceClassifier.getEmbeddings(croppedIdFace);
    final selfieEmbeddings = _faceClassifier.getEmbeddings(croppedSelfieFace);

    final matchScore = _faceClassifier.compareFaces(
      idEmbeddings,
      selfieEmbeddings,
    );

    setState(() {
      if (matchScore >= 80.0) {
        _verificationStatus =
            '✅ MATCHED SUCCESSFULLY! (${matchScore.toStringAsFixed(1)}% Confidence)\nThis person is the authorized ID owner.';
      } else {
        _verificationStatus =
            '❌ VERIFICATION FAILED (${matchScore.toStringAsFixed(1)}% Match)\nThe face does not match the ID owner.';
      }
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildFieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? 'Not detected' : value)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _faceDetector.close(); // I-close ang face detector para walang memory leak
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ID Card OCR & Face Match'),
        backgroundColor: Colors.amber,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SELECTION CARD
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step 1: Scan Front of ID Card',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickIdImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Capture ID Card'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _pickIdImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Pick from Gallery'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_idImageFile != null)
              Column(
                children: [
                  // ID DISPLAY
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _idImageFile!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // EXTRACTED TEXT FIELDS
                  const Text(
                    'Extracted Fields',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldRow('First Name', _firstName),
                        _buildFieldRow('Middle Name', _middleName),
                        _buildFieldRow('Last Name', _lastName),
                        _buildFieldRow('ID Number', _idNumber),
                        _buildFieldRow(
                          'Face Detected on ID',
                          _idHasFace ? 'Yes ✅' : 'No ❌',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(thickness: 2),
                  const SizedBox(height: 12),

                  // STEP 2: SELFIE VERIFICATION SECTION
                  const Text(
                    'Step 2: Face Verification (Selfie)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: _idCaptureSelfie,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                    ),
                    icon: const Icon(Icons.face),
                    label: const Text('Take a Selfie Photo'),
                  ),

                  if (_selfieImageFile != null) ...[
                    const SizedBox(height: 16),
                    CircleAvatar(
                      radius: 70,
                      backgroundImage: FileImage(_selfieImageFile!),
                    ),
                  ],

                  if (_verificationStatus.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _verificationStatus.contains('✅')
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _verificationStatus.contains('✅')
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                      child: Text(
                        _verificationStatus,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _verificationStatus.contains('✅')
                              ? Colors.green.shade900
                              : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Take a clear photo of the front of the ID card. The app will try to extract the text automatically.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
