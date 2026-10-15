import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// A picked text file, or why it was refused.
typedef PickedText = ({String? name, String? text, String? error});

/// Lets the user pick one file and reads it as UTF-8, refusing files over [maxBytes]
/// before reading them. Returns null when the user cancels.
Future<PickedText?> pickTextFile({
  required List<String> extensions,
  required int maxBytes,
}) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  if (files.isEmpty) return null;
  final f = files.first;
  final size = f.lengthSync() ?? await f.length();
  if (size != null && size > maxBytes) {
    return (
      name: f.name,
      text: null,
      error:
          'The file is ${(size / 1e6).toStringAsFixed(1)} MB. '
          'The limit is ${(maxBytes / 1e6).toStringAsFixed(0)} MB.',
    );
  }
  try {
    final text = utf8.decode(await f.readAsBytes());
    return (name: f.name, text: text, error: null);
  } on FormatException {
    return (name: f.name, text: null, error: 'The file is not UTF-8 text.');
  }
}

/// Saves or downloads [text] as a file (a browser download on the web).
Future<void> saveTextFile(String fileName, String text, String mimeType) =>
    FilePicker.saveFile(
      fileName: fileName,
      bytes: utf8.encode(text),
      mimeType: mimeType,
    );
