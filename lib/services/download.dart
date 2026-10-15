import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Saves [content] as a file in the browser's downloads.
void downloadText(String filename, String content, String mimeType) {
  final blob = web.Blob(
    [utf8.encode(content).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}

/// Opens [url] in a new browser tab.
void openUrl(String url) => web.window.open(url, '_blank');

/// Copies [text] to the clipboard.
Future<void> copyText(String text) =>
    web.window.navigator.clipboard.writeText(text).toDart;
