//import 'dart:nativewrappers/_internal/vm/lib/ffi_native_type_patch.dart';

import 'dart:async';
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
import 'package:tray_manager/tray_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:local_notifier/local_notifier.dart';

// CONFIGURA: percorsi dei file richiesti su Windows (UNC supportato)
// Esempio: r'\\SERVER\SHARE\Farmaconsult\file1.key'
const String kWinRequiredFile1 = r'\\canestrello\sys\mm5\maga.dbf';
const String kWinRequiredFile2 = r'\\canestrello\sys\pers\www\index.prg';
const String kTrayIconDefaultPath = 'windows/runner/resources/app_icon.ico';
// Range consentito per codici da clipboard (inclusivo)
const int kClipboardCodeMin = 0;      // usa 100000 per evitare zeri iniziali
const int kClipboardCodeMax = 999999; // 6 cifre

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    // Init notifications for Windows tray toasts
    try {
      await localNotifier.setup(appName: 'Farma authenticator');
    } catch (_) {}
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
      await windowManager.setMaximizable(false);
      await windowManager.show();
      await windowManager.focus();
      // Abilitiamo preventClose solo dopo l'inizializzazione del tray
      await windowManager.setPreventClose(false);
    });
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

class _ReverseHomePageState extends State<ReverseHomePage> with WindowListener, TrayListener {
  final TextEditingController _controller = TextEditingController();
  //final FlutterTts _tts = FlutterTts();
  String _generatedUUID = '';
  String _converted = '';
  bool _lAppAttiva = false;
  bool _autoSubmitted = false;
  int diff = 0;
  String _datascadenza = "";
  String _version = "";
  bool _trayInitialized = false;
  // Clipboard watcher
  Timer? _clipboardTimer;
  String? _lastClipboardSeen;
  bool _clipboardWatchEnabled = true;

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
    // Cambiato: proviamo SEMPRE a registrare e ottenere la data dal server.
    // In caso di errore rete/server, _registerDevice userà in fallback la data memorizzata.
    debugPrint("verifica/registrazione token dal server");
    _registerDevice(_uuid);
  }

  Future<void> _initSystemTray() async {
    if (!Platform.isWindows) return;
    final menu = Menu();
    menu.items = [
      MenuItem(key: 'show', label: 'Mostra finestra'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: 'Esci'),
    ];
    // Risolvi l'icona della tray da più posizioni possibili
    final exeDir = File(Platform.resolvedExecutable).parent;
    final iconCandidates = <String>[
      kTrayIconDefaultPath,
      'assets/tray_icon.ico',
      'assets/tray_icon.png',
      // Tentativi relativi alla cartella dell'eseguibile (build/release)
      '${exeDir.path}\\tray_icon.ico',
      '${exeDir.path}\\assets\\tray_icon.ico',
      '${exeDir.path}\\data\\tray_icon.ico',
      '${exeDir.path}\\data\\flutter_assets\\assets\\tray_icon.ico',
      // Asset inclusi mantenendo il percorso originale nel bundle
      '${exeDir.path}\\data\\flutter_assets\\windows\\runner\\resources\\tray_icon.ico',
      '${exeDir.path}\\data\\flutter_assets\\windows\\runner\\resources\\app_icon.ico',
      '${exeDir.path}\\app_icon.ico',
    ];
    String? resolvedIcon;
    for (final candidate in iconCandidates) {
      try {
        final file = File(candidate);
        if (await file.exists()) {
          resolvedIcon = file.absolute.path;
          break;
        }
      } catch (_) {}
    }
    bool hadIcon = false;
    if (resolvedIcon != null) {
      await trayManager.setIcon(resolvedIcon);
      hadIcon = true;
    } else {
      debugPrint(
          'Tray icon non trovata. Aggiungi un file .ico (es. assets/tray_icon.ico) e aggiorna pubspec o copia vicino all\'exe.');
    }
    await trayManager.setToolTip('Farma authenticator');
    await trayManager.setContextMenu(menu);
    _trayInitialized = hadIcon;
  }

  Future<void> _showFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() async {
    await _showFromTray();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (!Platform.isWindows) return;
    switch (menuItem.key) {
      case 'show':
        await _showFromTray();
        break;
      case 'exit':
        _trayInitialized = false;
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.close();
        break;
    }
  }

  @override
  void onWindowClose() async {
    if (!Platform.isWindows) {
      return;
    }
    final preventClose = await windowManager.isPreventClose();
    if (preventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (!Platform.isWindows) {
      return;
    }
    if (eventName == 'minimize') {
      // Nascondi alla tray solo se la tray è attiva, altrimenti lascia l'app minimizzata in taskbar
      if (_trayInitialized) {
        unawaited(windowManager.hide());
      }
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
        final dataDaServer = DateFormat(
          "dd-MM-yy",
        ).parse(resp.body);
        final attivaDaServer = dataDaServer.isAfter(DateTime.now()) || dataDaServer.isAtSameMomentAs(DateTime.now());
        final filesOk = await _windowsRequiredFilesPresent();
        setState(() {
          _lAppAttiva = attivaDaServer && (!Platform.isWindows || filesOk);
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
        // Fallback: usa la data memorizzata, se presente
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString("DataScadenza");
        final filesOk = await _windowsRequiredFilesPresent();
        bool attiva = false;
        if (stored != null && stored.isNotEmpty) {
          try {
            attiva = DateFormat("dd-MM-yy").parse(stored).isAfter(DateTime.now()) || DateFormat("dd-MM-yy").parse(stored).isAtSameMomentAs(DateTime.now());
          } catch (_) {}
        }
        setState(() {
          _datascadenza = stored ?? '';
          _lAppAttiva = attiva && (!Platform.isWindows || filesOk);
        });
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Errore server: ${resp.statusCode}. Uso data salvata: ${_datascadenza.isEmpty ? 'nessuna' : _datascadenza}'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      debugPrint('Errore rete: $e');
      // Fallback: usa la data memorizzata, se presente
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString("DataScadenza");
      final filesOk = await _windowsRequiredFilesPresent();
      bool attiva = false;
      if (stored != null && stored.isNotEmpty) {
        try {
          attiva = DateFormat("dd-MM-yy").parse(stored).isAfter(DateTime.now());
        } catch (_) {}
      }
      setState(() {
        _datascadenza = stored ?? '';
        _lAppAttiva = attiva && (!Platform.isWindows || filesOk);
      });
      ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Errore rete. Uso data salvata: ${_datascadenza.isEmpty ? 'nessuna' : _datascadenza}'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
    }
  }

  Future<String> getDeviceBasedUuid() async {
    final di = DeviceInfoPlugin();

    // Windows: usa il nome del computer
    if (Platform.isWindows) {
      final envName = Platform.environment['COMPUTERNAME'];
      if (envName != null && envName.isNotEmpty) {
        return envName;
      }
      // Fallback generico
      return Platform.localHostname;
    }

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

  // Verifica presenza di due file obbligatori solo su Windows
  Future<bool> _windowsRequiredFilesPresent() async {
    if (!Platform.isWindows) return true;
    try {
      final p1 = Platform.environment['FARMA_FILE1_PATH'] ?? kWinRequiredFile1;
      final p2 = Platform.environment['FARMA_FILE2_PATH'] ?? kWinRequiredFile2;
      final f1 = File(p1);
      final f2 = File(p2);
      final e1 = await f1.exists().timeout(const Duration(seconds: 2), onTimeout: () => false);
      final e2 = await f2.exists().timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!e1 || !e2) {
        debugPrint('File richiesti non trovati su Windows: e1=$e1 path1=$p1, e2=$e2 path2=$p2');
      }
      return e1 && e2;
    } catch (_) {
      return false;
    }
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
      // Copia automatica negli appunti solo su Windows
      if (Platform.isWindows && _converted.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: _converted));
        // Feedback: SnackBar se visibile, altrimenti notifica di sistema
        try {
          final isVisible = await windowManager.isVisible();
          if (mounted && isVisible) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Codice copiato negli appunti'),
                  duration: Duration(milliseconds: 900),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          } else {
            // Toast in tray area
            final n = LocalNotification(
              title: 'Farma authenticator',
              body: 'Codice copiato: ' + _converted,
            );
            await n.show();
          }
        } catch (_) {}
      }
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
    if (Platform.isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      // Inizializza la tray e abilita preventClose solo se disponibile
      unawaited(_initSystemTray().then((_) async {
        if (_trayInitialized) {
          await windowManager.setPreventClose(true);
        } else {
          await windowManager.setPreventClose(false);
        }
      }));
    }
    _startClipboardWatcher();
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      if (_trayInitialized) {
        unawaited(trayManager.destroy());
      }
    }
    _stopClipboardWatcher();
    _controller.dispose();
    super.dispose();
  }

  void _startClipboardWatcher() {
    if (!Platform.isWindows) return; // abilita solo su Windows (modifica se vuoi)
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!_clipboardWatchEnabled) return;
      _checkClipboardForCode();
    });
  }

  void _stopClipboardWatcher() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
  }

  String _digitsOnly(String s) {
    final sb = StringBuffer();
    for (final cu in s.codeUnits) {
      if (cu >= 0x30 && cu <= 0x39) { // '0'..'9'
        sb.writeCharCode(cu);
      }
    }
    return sb.toString();
  }

  Future<void> _checkClipboardForCode() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty || text == _lastClipboardSeen) return;
      // Strict: accetta solo se la clipboard contiene ESATTAMENTE 6 cifre (nessun separatore)
      _lastClipboardSeen = text;
      final t = text.trim();
      if (t.length != 6) return;
      bool allDigits = true;
      for (final cu in t.codeUnits) {
        if (cu < 0x30 || cu > 0x39) { // '0'..'9'
          allDigits = false;
          break;
        }
      }
      if (!allDigits) return; // es. "20-12-12" non viene accettato
      final value = int.tryParse(t);
      if (value == null || value < kClipboardCodeMin || value > kClipboardCodeMax) return;
      if (!mounted) return;
      final hasFocus = FocusScope.of(context).hasFocus;
      final userTyping = hasFocus && _controller.text.isNotEmpty;
      if (userTyping) return;
      _controller.text = t;
      _autoSubmitted = false;
      _controller.selection = const TextSelection.collapsed(offset: 6);
      _handleTextChanged(t);
      return;

      // cerca esattamente 6 cifre isolate
      // ignore: unused_local_variable
      
      
    } catch (_) {
      // ignora errori clipboard
    }
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
                  keyboardType: Platform.isWindows ? TextInputType.none : TextInputType.number,
                  readOnly: Platform.isWindows ? false : true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'es: 123456',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onTap: () {
                    if (Platform.isWindows) {
                      SystemChannels.textInput.invokeMethod('TextInput.hide');
                    }
                  },
                  onChanged: _handleTextChanged,
                ),
                if (!Platform.isWindows) ...[
                  const SizedBox(height: 12),
                  _NumericKeypad(
                    onDigit: _appendDigit,
                    onBackspace: _deleteLast,
                    onClear: _clearAll,
                  ),
                  const SizedBox(height: 8),
                ],
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
              GestureDetector(
                onTap: _showUuidLens,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: _lAppAttiva ? 'App attiva' : 'App non attiva',
                      child: _StatusLed(on: _lAppAttiva, size: 10),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _generatedUUID,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
              ),
          )],
          ),
        ),
      ),
    );
  }
}

// ---- Helpers per la pulsantiera numerica ----
extension on _ReverseHomePageState {
  void _showUuidLens() {
    if (_generatedUUID.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ID dispositivo',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _generatedUUID,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontFamily: 'monospace',
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _extractLastDigits(String s, int n) {
    final digitsOnly = s.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return '';
    return digitsOnly.length <= n
        ? digitsOnly
        : digitsOnly.substring(digitsOnly.length - n);
  }

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

class _StatusLed extends StatelessWidget {
  final bool on;
  final double size;

  const _StatusLed({required this.on, this.size = 10});

  @override
  Widget build(BuildContext context) {
    final color = on ? Colors.green : Colors.red;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26, width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}


