import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Copies text to clipboard using document.execCommand('copy') via a temporary
/// textarea element. This works on plain HTTP (no secure context required),
/// unlike navigator.clipboard.writeText().
void writeToClipboard(String text) {
  final doc = globalContext['document']! as JSObject;

  // Create a temporary textarea
  final textarea = doc.callMethod<JSObject>('createElement'.toJS, 'textarea'.toJS);
  textarea['value'] = text.toJS;
  textarea['style'] = 'position:fixed;left:-9999px;top:-9999px'.toJS;

  // Append, select, copy, remove
  (doc['body']! as JSObject).callMethod<JSObject>('appendChild'.toJS, textarea);
  textarea.callMethod<JSAny?>('select'.toJS);
  doc.callMethod<JSAny?>('execCommand'.toJS, 'copy'.toJS);
  (doc['body']! as JSObject).callMethod<JSObject>('removeChild'.toJS, textarea);
}
