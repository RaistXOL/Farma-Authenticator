//import 'dart:nativewrappers/_internal/vm/lib/ffi_native_type_patch.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
//import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:android_id/android_id.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = WindowOptions(
      size: Size(300, 310),
      minimumSize: Size(300, 310),
      maximumSize: Size(300, 310),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "Farma authenticator",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    //windowManager.setPreventClose(true);
  }
  runApp(const ReverseApp());
}

class ReverseApp extends StatelessWidget {
  const ReverseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farma auth',
      home: const ReverseHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ReverseHomePage extends StatefulWidget {
  const ReverseHomePage({super.key});

  @override
  State<ReverseHomePage> createState() => _ReverseHomePageState();
}

class _ReverseHomePageState extends State<ReverseHomePage> with WindowListener {
  final TextEditingController _controller = TextEditingController();
  //final FlutterTts _tts = FlutterTts();
  String _generatedUUID = '';
  String _converted = '';
  bool _lAppAttiva = false;
  bool _autoSubmitted = false;
  int diff = 0;
  String _datascadenza = "";
  String _version = "";

  void _initUuid() async {
    final _uuid = await getDeviceBasedUuid();

    final prefs = await SharedPreferences.getInstance();
    final datascadenza = prefs.getString("DataScadenza");

    setState(() {
      _generatedUUID = _uuid;

      if (datascadenza != null && datascadenza.isNotEmpty) {
        _datascadenza = DateFormat(
          "dd-MM-yy",
        ).format(DateFormat("dd-MM-yy").parse(datascadenza));
      } else {
        _datascadenza = '';
      }
    });

    if (datascadenza == null ||
        datascadenza.isEmpty == true ||
        DateTime.now().isAfter(DateFormat("dd-MM-yy").parse(datascadenza))) {
      debugPrint("richiesto rinnovo token");
      _registerDevice(_uuid);
      //_datascadenza = DateFormat("dd-MM-yy").format(DateTime.now());
    } else {
      debugPrint("token ancora valido: data scadenza $datascadenza");
      setState(() {
        _lAppAttiva = true;
      });
    }
  }

  void _getVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
    });
  }

  Future<void> _registerDevice(String deviceId) async {
    final uri = Uri.parse(
      'https://www.farmaconsult.it/riservate/farma_auth.prg',
    ); // ← cambia URL
    final headers = {'Content-Type': 'application/x-www-form-urlencoded'};

    try {
      final resp = await http
          .post(
            uri,
            headers: headers,
            body: {
              'device_id': deviceId,
              'platform': Theme.of(context).platform.name,
              'version': _version,
            },
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        setState(() {
          _lAppAttiva = DateFormat(
            "dd-MM-yy",
          ).parse(resp.body).isAfter(DateTime.now());
          debugPrint('Registrazione ${_lAppAttiva ? 'ok' : 'fallita'}');
          _datascadenza = resp.body;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          "DataScadenza",
          resp.body, //DateFormat("dd-MM-yy").format(DateTime.now()).toString(),
        );
      } else {
        debugPrint('Errore server: ${resp.statusCode} - ${resp.body}');
      }
    } catch (e) {
      debugPrint('Errore rete: $e');
    }
  }

  Future<String> getDeviceBasedUuid() async {
    final di = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await di.androidInfo;

      const androidId = AndroidId();
      final id = await androidId.getId();
      if (id != null) {
        return id;
      }
      // Fallback (non perfetto)
      final raw = '${info.brand}|${info.model}|${info.fingerprint}';
      return sha256.convert(utf8.encode(raw)).toString();
    }

    if (Platform.isIOS) {
      final info = await di.iosInfo;
      final idfv = info
          .identifierForVendor; // stabile finché non disinstalli tutte le app dello stesso vendor
      if (idfv != null && idfv.isNotEmpty) {
        return idfv;
        // return sha256.convert(utf8.encode(idfv)).toString();
      }
      // Fallback (non perfetto)
      final raw = '${info.name}|${info.model}|${info.systemVersion}';
      return sha256.convert(utf8.encode(raw)).toString();
    }
    return 'unknown-device';
  }

  Future<void> _convertiInBase32() async {
    final input = "123${_controller.text}";
    try {
      final int decimalValue = int.parse(input);
      final String base32 = _toBase32(decimalValue);
      setState(() {
        _converted =
            '${base32[2]}${base32[5]}${base32[1]}${base32[3]}'; //base32;
      });
      //_tts.setLanguage('it-IT');
      //_tts.setSpeechRate(0.5); // più lento
      //await _tts.speak( "il codice generato è. " + _converted.split('').join('.'));
      //await _salvaDataScadenza(DateTime.now());
    } catch (e) {
      setState(() {
        _converted = 'Inserisci un codice valido.';
      });
    }
  }

  String _toBase32(int number) {
    const String base32Chars = '0123456789BCDFGHJKLMNPQRSTUVWXYZ';
    if (number == 0) return '0';
    String result = '';
    while (number > 0) {
      result = base32Chars[number % 32] + result;
      number ~/= 32;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _getVersion();
    _initUuid();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Platform.isWindows
          ? null
          : AppBar(title: const Text('Farma authenticator')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Codice generato in alto
                Text(
                  _converted,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                //const Text('Inserisci codice:'),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.normal),
                  readOnly: true, // input solo da pulsantiera
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'inserisci codice es: 123456',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: _handleTextChanged,
                ),
                const SizedBox(height: 12),
                _NumericKeypad(
                  onDigit: _appendDigit,
                  onBackspace: _deleteLast,
                  onClear: _clearAll,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "versione: $_version scadenza: $_datascadenza",
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                _generatedUUID, // ← Cambia il testo come vuoi
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Helpers per la pulsantiera numerica ----
extension on _ReverseHomePageState {
  void _handleTextChanged(String value) {
    if (value.length > 6) {
      final truncated = value.substring(0, 6);
      _controller.text = truncated;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: truncated.length),
      );
    }

    setState(() {});

    if (_controller.text.length == 6 && !_autoSubmitted) {
      _autoSubmitted = true;
      FocusScope.of(context).unfocus();
      if (_lAppAttiva) {
        _convertiInBase32();
      } else {
        // Avvisa l'utente che l'app non è attiva
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('App non attiva: impossibile generare il codice.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }

    if (_controller.text.length < 6) {
      _autoSubmitted = false;
      _converted = '';
    }
  }

  void _appendDigit(String digit) {
    if (_controller.text.length >= 6) {
      final newText = digit; // reset e riparti dal nuovo numero
      _controller.text = newText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
      _handleTextChanged(newText);
      return;
    }
    final newText = _controller.text + digit;
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
    _handleTextChanged(newText);
  }

  void _deleteLast() {
    if (_controller.text.isEmpty) return;
    final newText = _controller.text.substring(0, _controller.text.length - 1);
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
    _handleTextChanged(newText);
  }

  void _clearAll() {
    _controller.clear();
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _handleTextChanged('');
  }
}

class _NumericKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  const _NumericKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.1, // compattiamo per finestre piccole
          children: [
            for (final d in digits)
              ElevatedButton(
                onPressed: () => onDigit(d),
                child: Text(d, style: const TextStyle(fontSize: 25)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.1,
          children: [
            Tooltip(
              message: 'Cancella',
              child: ElevatedButton(
                onPressed: onBackspace,
                child: const Icon(Icons.backspace_outlined, size: 25),
              ),
            ),
            ElevatedButton(
              onPressed: () => onDigit('0'),
              child: const Text('0', style: TextStyle(fontSize: 25)),
            ),
            Tooltip(
              message: 'Azzera',
              child: ElevatedButton(
                onPressed: onClear,
                child: const Icon(Icons.cancel, size: 25, color: Colors.red ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
