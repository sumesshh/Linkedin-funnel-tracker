import 'dart:convert';
import 'dart:js_interop';

import 'package:intl/intl.dart';
import 'package:web/web.dart' as web;

import '../data/repository.dart';
import 'download.dart';

/// Downloads the whole database as a .json file.
void exportJson() {
  final json = const JsonEncoder.withIndent('  ')
      .convert(Repository.instance.exportData());
  downloadText(
    'linkedin-dashboard-backup-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json',
    json,
    'application/json',
  );
}

/// Opens a file picker and returns the parsed JSON, or null if the user
/// picked nothing.
Future<Map<String, dynamic>?> pickJsonFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json';
  input.click();
  await input.onChange.first;
  final file = input.files?.item(0);
  if (file == null) return null;
  final text = (await file.text().toDart).toDart;
  final data = jsonDecode(text);
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Not a dashboard backup file.');
  }
  return data;
}
