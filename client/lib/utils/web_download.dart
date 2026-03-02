import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadTextFile(String content, String filename) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/markdown');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Copy text to clipboard using legacy execCommand (works on HTTP).
bool copyToClipboard(String text) {
  final ta = html.TextAreaElement();
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  html.document.body?.append(ta);
  ta.select();
  final ok = html.document.execCommand('copy');
  ta.remove();
  return ok;
}
