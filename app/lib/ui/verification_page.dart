import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../state/matrix_service.dart';
import 'scope.dart';

/// Öffnet die [VerificationPage], sobald eine Verifizierung beginnt, egal ob
/// hier gestartet oder von einem anderen Gerät angefragt.
class VerificationListener extends StatefulWidget {
  const VerificationListener({
    super.key,
    required this.navigator,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<VerificationListener> createState() => _VerificationListenerState();
}

class _VerificationListenerState extends State<VerificationListener> {
  MatrixService? _matrix;
  KeyVerification? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final matrix = MatrixScope.maybeOf(context);
    if (matrix == _matrix) return;
    _matrix?.removeListener(_check);
    _matrix = matrix?..addListener(_check);
  }

  @override
  void dispose() {
    _matrix?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final request = _matrix?.verification;
    if (request == null || request == _shown) return;
    _shown = request;
    widget.navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => VerificationPage(request)),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Führt durch eine Verifizierung: annehmen, Emojis vergleichen, fertig.
class VerificationPage extends StatelessWidget {
  const VerificationPage(this.request, {super.key});

  final KeyVerification request;

  @override
  Widget build(BuildContext context) {
    // Baut bei jedem Schritt neu: MatrixService meldet die Änderungen.
    final matrix = MatrixScope.maybeOf(context)!;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && matrix.verification == request) {
          matrix.closeVerification();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Gerät verifizieren')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: _steps(context, matrix),
        ),
      ),
    );
  }

  List<Widget> _steps(BuildContext context, MatrixService matrix) {
    final theme = Theme.of(context);
    void close() => Navigator.of(context).maybePop();
    final other = request.userId == matrix.userId
        ? 'Dein anderes Gerät'
        : request.userId;

    return switch (request.state) {
      KeyVerificationState.askAccept => [
        Text(
          '$other möchte dieses Gerät verifizieren.',
          style: theme.textTheme.titleMedium,
        ),
        if (request.userId == matrix.userId &&
            matrix.sessionTrust != SessionTrust.verified) ...[
          const SizedBox(height: 16),
          const Text(
            'Dieses Gerät ist selbst nicht verifiziert. Ist das andere Gerät '
            'auch nicht verifiziert, bleibt es das nach dem Vergleich. Richte '
            'dann zuerst unter „Matrix-Konto“ die Verifizierung ein oder setze '
            'sie dort zurück.',
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: request.acceptVerification,
          child: const Text('Annehmen'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: close, child: const Text('Ablehnen')),
      ],
      KeyVerificationState.askChoice => [
        const Text('Vergleicht auf beiden Geräten dieselben Emojis.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => request.continueVerification(EventTypes.Sas),
          child: const Text('Emojis vergleichen'),
        ),
      ],
      KeyVerificationState.askSSSS => [_RecoveryKeyStep(request)],
      KeyVerificationState.askSas => _compare(context),
      KeyVerificationState.waitingAccept => _waiting(
        context,
        request.userId == matrix.userId
            ? 'Bitte auf einem anderen angemeldeten Gerät bestätigen, '
                  'z. B. in Element.'
            : 'Warte auf $other …',
      ),
      KeyVerificationState.waitingSas => _waiting(
        context,
        'Warte auf die Bestätigung des anderen Geräts …',
      ),
      KeyVerificationState.done => [
        Icon(Icons.verified_user, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        const Text('Verifiziert.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: close, child: const Text('Fertig')),
      ],
      KeyVerificationState.error => [
        Icon(Icons.gpp_bad_outlined, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(_cancelText, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: close, child: const Text('Schließen')),
      ],
      // QR-Codes bietet Konsum nicht an, diese Zustände kommen nicht vor.
      KeyVerificationState.showQRSuccess ||
      KeyVerificationState.confirmQRScan => _waiting(context, ''),
    };
  }

  List<Widget> _waiting(BuildContext context, String text) => [
    const Center(child: CircularProgressIndicator()),
    const SizedBox(height: 16),
    Text(text, textAlign: TextAlign.center),
    const SizedBox(height: 24),
    OutlinedButton(
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Text('Abbrechen'),
    ),
  ];

  List<Widget> _compare(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = request.sasTypes.contains('emoji');
    return [
      Text(
        emoji
            ? 'Erscheinen auf dem anderen Gerät dieselben Emojis in derselben '
                  'Reihenfolge?'
            : 'Erscheinen auf dem anderen Gerät dieselben Zahlen?',
      ),
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: emoji
            ? [
                for (final e in request.sasEmojis)
                  SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        Text(e.emoji, style: const TextStyle(fontSize: 40)),
                        Text(
                          e.name,
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              ]
            : [
                for (final n in request.sasNumbers)
                  Text('$n', style: theme.textTheme.headlineMedium),
              ],
      ),
      const SizedBox(height: 32),
      FilledButton(
        onPressed: request.acceptSas,
        child: const Text('Stimmen überein'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: request.rejectSas,
        child: const Text('Stimmen nicht überein'),
      ),
    ];
  }

  String get _cancelText => switch (request.canceledCode) {
    'm.user' => 'Abgebrochen.',
    'm.timeout' => 'Zeit abgelaufen.',
    'm.mismatched_sas' ||
    'm.key_mismatch' => 'Die Emojis stimmten nicht überein.',
    'm.unknown_method' => 'Das andere Gerät kennt kein gemeinsames Verfahren.',
    'm.accepted' => 'Auf einem anderen Gerät angenommen.',
    _ =>
      'Verifizierung fehlgeschlagen: '
          '${request.canceledReason ?? request.canceledCode ?? 'unbekannt'}',
  };
}

/// Nach dem Vergleich braucht das SDK ggf. die Schlüssel aus dem
/// Schlüsselspeicher des Kontos, um das andere Gerät zu signieren.
class _RecoveryKeyStep extends StatefulWidget {
  const _RecoveryKeyStep(this.request);

  final KeyVerification request;

  @override
  State<_RecoveryKeyStep> createState() => _RecoveryKeyStepState();
}

class _RecoveryKeyStepState extends State<_RecoveryKeyStep> {
  final _key = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _open({bool skip = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.request.openSSSS(
        keyOrPassphrase: skip ? null : _key.text.trim(),
        skip: skip,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Schlüssel oder Passphrase stimmt nicht');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Um das andere Gerät auch für deine übrigen Geräte zu bestätigen, '
        'gib den Wiederherstellungsschlüssel oder die Sicherheits-Passphrase '
        'deines Kontos ein.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _key,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Wiederherstellungsschlüssel oder Passphrase',
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _open,
        child: const Text('Weiter'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _open(skip: true),
        child: const Text('Überspringen'),
      ),
    ],
  );
}
