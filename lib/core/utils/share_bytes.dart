import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes downloaded bytes to a temp file and opens the system share sheet.
Future<void> shareDownloadedBytes({
  required List<int> bytes,
  required String filename,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)], text: text);
}
