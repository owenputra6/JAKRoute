import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

/// Browser speech-to-text (Web Speech API), same hand-rolled JS interop
/// style as the geolocation code in station_map.dart — no extra package.
/// Chrome/Edge only; [isSupported] is false elsewhere and the mic button
/// hides itself rather than showing something that silently fails.
class SpeechInput {
  static bool get isSupported {
    try {
      return globalContext.has('webkitSpeechRecognition') || globalContext.has('SpeechRecognition');
    } catch (_) {
      return false;
    }
  }

  JSObject? _rec;
  bool get isListening => _rec != null;

  /// Starts one listening session. [onResult] fires once with the final
  /// transcript; [onDone] always fires when the session ends (result,
  /// error, or manual [stop]) so the caller can reset its mic icon.
  void start({required ValueChanged<String> onResult, required VoidCallback onDone, VoidCallback? onError}) {
    if (!isSupported || _rec != null) return;
    try {
      final ctorAny = globalContext.getProperty<JSAny?>('webkitSpeechRecognition'.toJS) ??
          globalContext.getProperty<JSAny?>('SpeechRecognition'.toJS);
      final ctor = ctorAny as JSFunction;
      final rec = ctor.callAsConstructor<JSObject>();
      rec
        ..setProperty('lang'.toJS, 'id-ID'.toJS)
        ..setProperty('interimResults'.toJS, false.toJS)
        ..setProperty('continuous'.toJS, false.toJS)
        ..setProperty(
          'onresult'.toJS,
          ((JSObject e) {
            final results = e.getProperty<JSObject?>('results'.toJS);
            final first = results?.getProperty<JSObject?>(0.toJS);
            final alt = first?.getProperty<JSObject?>(0.toJS);
            final text = alt?.getProperty<JSString?>('transcript'.toJS)?.toDart;
            if (text != null && text.isNotEmpty) onResult(text);
          }).toJS,
        )
        ..setProperty('onerror'.toJS, ((JSObject _) => onError?.call()).toJS)
        ..setProperty(
          'onend'.toJS,
          (() {
            _rec = null;
            onDone();
          }).toJS,
        );
      _rec = rec;
      rec.callMethod('start'.toJS);
    } catch (_) {
      _rec = null;
      onError?.call();
    }
  }

  void stop() {
    try {
      _rec?.callMethod('stop'.toJS);
    } catch (_) {}
  }
}
