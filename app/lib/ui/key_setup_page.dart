import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/key_setup.dart';
import '../state/matrix_service.dart';
import 'scope.dart';

/// Richtet die Geräte-Verifizierung ein oder setzt die Identität zurück und
/// zeigt den neuen Wiederherstellungsschlüssel.
class KeySetupPage extends StatefulWidget {
  const KeySetupPage({super.key, required this.reset});

  /// Vorhandene Identität ersetzen statt erstmals einrichten.
  final bool reset;

  @override
  State<KeySetupPage> createState() => _KeySetupPageState();
}

class _KeySetupPageState extends State<KeySetupPage> {
  KeySetup? _setup;
  final _password = TextEditingController();
  bool _saved = false;

  @override
  void dispose() {
    _setup?.dispose();
    _password.dispose();
    super.dispose();
  }

  void _start(MatrixService matrix) {
    try {
      setState(() => _setup = matrix.startKeySetup()..addListener(_changed));
    } on StateError catch (e) {
      AppScope.of(context).status.show(e.message);
    }
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final matrix = MatrixScope.maybeOf(context)!;
    final setup = _setup;
    // Nicht mitten im Hochladen weg, und nicht, bevor der neue Schlüssel
    // aufbewahrt ist: Er wäre sonst verloren.
    final canPop = switch (setup?.step) {
      KeySetupStep.working => false,
      KeySetupStep.done => _saved,
      _ => true,
    };
    return PopScope(
      canPop: canPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.reset
                ? 'Identität zurücksetzen'
                : 'Verifizierung einrichten',
          ),
          automaticallyImplyLeading: canPop,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: setup == null ? _intro(matrix) : _steps(setup),
        ),
      ),
    );
  }

  List<Widget> _intro(MatrixService matrix) => [
    Text(
      widget.reset
          ? 'Konsum erzeugt neue Schlüssel für dein Konto und einen neuen '
                'Wiederherstellungsschlüssel. Danach ist dieses Gerät '
                'verifiziert.\n\n'
                'Deine anderen Geräte und Apps (z. B. Element) gelten danach '
                'als nicht verifiziert. Bestätige sie anschließend mit diesem '
                'Gerät. Verschlüsselte Nachrichten, die nur der alte '
                'Schlüsselspeicher kannte, lassen sich womöglich nicht mehr '
                'lesen. Deine Konsum-Listen sind davon nicht betroffen.'
          : 'Damit du weitere Geräte und andere Matrix-Apps (z. B. Element) '
                'für dein Konto bestätigen kannst, erzeugt Konsum jetzt die '
                'Schlüssel dafür und einen Wiederherstellungsschlüssel.\n\n'
                'Mit dem Wiederherstellungsschlüssel bestätigst du ein Gerät '
                'auch dann, wenn kein anderes mehr angemeldet ist. Bewahre ihn '
                'sicher auf, z. B. in einem Passwort-Manager.',
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: () => _start(matrix),
      child: Text(widget.reset ? 'Zurücksetzen' : 'Einrichten'),
    ),
  ];

  List<Widget> _steps(KeySetup setup) {
    final theme = Theme.of(context);
    return switch (setup.step) {
      KeySetupStep.working => const [
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 16),
        Text('Schlüssel werden erzeugt …', textAlign: TextAlign.center),
      ],
      KeySetupStep.approveInBrowser => [
        Text(
          setup.retry
              ? 'Der Server hat noch keine Bestätigung. Bitte auf seiner '
                    'Seite das Zurücksetzen erlauben und dann erneut „Weiter“ '
                    'tippen.'
              : 'Dein Server will das Ersetzen der Schlüssel bestätigt haben. '
                    'Erlaube es auf seiner Seite im Browser und komm dann '
                    'hierher zurück.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Im Browser bestätigen'),
          onPressed: () => launchUrl(
            setup.approvalUrl!,
            mode: LaunchMode.externalApplication,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: setup.approved, child: const Text('Weiter')),
        TextButton(onPressed: setup.cancel, child: const Text('Abbrechen')),
      ],
      KeySetupStep.password => [
        const Text('Bitte gib zur Bestätigung das Passwort deines Kontos ein.'),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Passwort',
            border: const OutlineInputBorder(),
            errorText: setup.retry ? 'Passwort stimmt nicht' : null,
          ),
          onSubmitted: (_) => setup.submitPassword(_password.text),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => setup.submitPassword(_password.text),
          child: const Text('Weiter'),
        ),
        TextButton(onPressed: setup.cancel, child: const Text('Abbrechen')),
      ],
      KeySetupStep.done => [
        Icon(Icons.verified_user, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Eingerichtet. Das ist dein Wiederherstellungsschlüssel. Schreib ihn '
          'auf oder speichere ihn in einem Passwort-Manager. Konsum zeigt ihn '
          'nicht noch einmal an.',
        ),
        const SizedBox(height: 16),
        SelectableText(
          setup.recoveryKey!,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Kopieren'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: setup.recoveryKey!));
            if (mounted) {
              AppScope.of(context).status.show('Schlüssel kopiert');
            }
          },
        ),
        CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          title: const Text('Ich habe den Schlüssel sicher aufbewahrt'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saved ? () => Navigator.of(context).pop() : null,
          child: const Text('Fertig'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Andere Geräte bestätigst du jetzt so: Dort „Mit anderem Gerät '
          'verifizieren“ wählen, hier die Anfrage annehmen und die Emojis '
          'vergleichen.',
        ),
      ],
      KeySetupStep.failed => [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'Nicht eingerichtet: ${setup.error ?? 'unbekannter Fehler'}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    };
  }
}
