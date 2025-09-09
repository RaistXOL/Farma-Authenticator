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
    setState((){
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Inserisci codice:'),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLength: 6,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Es: 123456',
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.backspace),
                        onPressed: () {
                          setState(() {
                            if (_controller.text.isNotEmpty) {
                              _controller.text = _controller.text.substring(
                                0,
                                _controller.text.length - 1,
                              );
                              _controller
                                  .selection = TextSelection.fromPosition(
                                TextPosition(offset: _controller.text.length),
                              );
                            }
                            // se torniamo sotto le 6 cifre, sblocca il prossimo auto-submit
                            if (_controller.text.length < 6) _converted = "";
                            _autoSubmitted = false;
                          });
                        },
                      )
                    : null,
              ),
              inputFormatters: [
                // consenti solo cifre e limita a 6
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (value) {
                // tronca eventuali incolli > 6 (per sicurezza)
                if (value.length > 6) {
                  final truncated = value.substring(0, 6);
                  _controller.text = truncated;
                  _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: truncated.length),
                  );
                }

                setState(() {}); // aggiorna la UI (icona backspace ecc.)

                // auto-submit quando sono 6 cifre, una sola volta
                if (value.length == 6 && !_autoSubmitted) {
                  _autoSubmitted = true;

                  // opzionale: chiudi tastiera/focus (utile su mobile/desktop)
                  FocusScope.of(context).unfocus();

                  if (_lAppAttiva) {
                    _convertiInBase32();
                  } else {
                    // opzionale: mostra/snack o stato "App scaduta"
                    debugPrint('App non attiva, non eseguo conversione');
                  }
                }

                // se l’utente modifica tornando <6, riabilita auto-submit
                if (value.length < 6) {
                  _autoSubmitted = false;
                  _converted = '';
                }
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _lAppAttiva ? _convertiInBase32 : null,
              child: _lAppAttiva ? Text('Genera codice') : Text('App scaduta'),
            ),
            const SizedBox(height: 20),
            Text(_converted, style: const TextStyle(fontSize: 24)),
          ],
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
                  fontSize: 10,
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
