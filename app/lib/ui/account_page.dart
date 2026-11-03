import 'package:flutter/material.dart';

import '../state/matrix_service.dart';
import 'dialogs.dart';
import 'key_setup_page.dart';
import 'scope.dart';

/// Anmeldung am Matrix-Server oder neues Konto anlegen.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _server = TextEditingController(text: 'matrix.org');
  final _user = TextEditingController();
  final _password = TextEditingController();

  /// Ergebnis der Server-Prüfung; null, solange noch kein Server gewählt ist.
  ServerLogin? _login;
  bool _showPassword = false;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _check(MatrixService matrix) async {
    final login = await matrix.checkServer(_server.text);
    if (!mounted) return;
    setState(() {
      _login = login;
      _showPassword = login != null && !login.browser;
    });
  }

  @override
  Widget build(BuildContext context) {
    final matrix = MatrixScope.maybeOf(context);
    if (matrix == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Matrix-Konto')),
        body: const Center(child: Text('Matrix ist nicht verfügbar.')),
      );
    }
    final login = _login;
    return Scaffold(
      appBar: AppBar(title: const Text('Matrix-Konto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (matrix.isLoggedIn) ...[
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(matrix.userId ?? ''),
              subtitle: Text(matrix.homeserver ?? ''),
            ),
            ..._trust(matrix),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Abmelden'),
              onPressed: matrix.busy ? null : () => _logout(matrix),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('Konto löschen …'),
              onPressed: matrix.busy ? null : () => _deleteAccount(matrix),
            ),
          ] else if (login == null)
            ..._serverStep(matrix)
          else
            ..._loginStep(matrix, login),
          if (matrix.waitingForBrowser) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            const Text(
              'Warte auf die Anmeldung im Browser …',
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: matrix.cancelBrowserLogin,
              child: const Text('Abbrechen'),
            ),
          ] else if (matrix.busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (matrix.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                matrix.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  /// Ob dieses Gerät verifiziert ist, und wie man es verifiziert.
  List<Widget> _trust(MatrixService matrix) {
    final busy = matrix.busy;
    return switch (matrix.sessionTrust) {
      SessionTrust.unknown => const [],
      SessionTrust.verified => const [
        ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text('Dieses Gerät ist verifiziert'),
          subtitle: Text(
            'Andere Geräte und Apps (z. B. Element) bestätigst du, indem du '
            'dort die Verifizierung mit einem anderen Gerät startest und die '
            'Anfrage hier annimmst.',
          ),
        ),
      ],
      SessionTrust.noCrossSigning => [
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Geräte-Verifizierung nicht eingerichtet'),
          subtitle: Text(
            'Richte sie ein, damit du weitere Geräte und andere Matrix-Apps '
            '(z. B. Element) mit diesem Gerät bestätigen kannst.',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Einrichten'),
          onPressed: busy ? null : () => _keySetup(reset: false),
        ),
      ],
      SessionTrust.unverified => [
        const ListTile(
          leading: Icon(Icons.gpp_maybe_outlined),
          title: Text('Dieses Gerät ist nicht verifiziert'),
          subtitle: Text(
            'Andere sehen es als unbekanntes Gerät. Bestätige es mit einem '
            'anderen angemeldeten Gerät oder dem Wiederherstellungsschlüssel.',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.devices_outlined),
          label: const Text('Mit anderem Gerät verifizieren'),
          onPressed: busy ? null : matrix.verifyWithOtherDevice,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.key_outlined),
          label: const Text('Mit Wiederherstellungsschlüssel'),
          onPressed: busy ? null : () => _recoveryKey(matrix),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : () => _keySetup(reset: true),
          child: const Text(
            'Kein verifiziertes Gerät und kein Schlüssel? Zurücksetzen …',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    };
  }

  Future<void> _keySetup({required bool reset}) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => KeySetupPage(reset: reset)));

  /// Abmelden; vorher fragen, was mit den Matrix-Gruppen geschieht.
  Future<void> _logout(MatrixService matrix) async {
    final groups = matrix.sharedGroups;
    if (groups.isEmpty) {
      await matrix.logout(keepGroups: false);
      return;
    }
    final unsent = groups.any((g) => !g.outbox.isEmpty);
    final names = groups.map((g) => '„${g.info.name}“').join(', ');
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abmelden'),
        content: Text(
          'Was soll mit den geteilten Gruppen ($names) auf diesem Gerät '
          'geschehen?\n\n'
          'Behältst du sie, bleiben sie als lokale Kopie mit dem Zusatz '
          '„(lokal)“ erhalten, werden aber nicht mehr abgeglichen: Änderungen '
          'daran erreichen die anderen Mitglieder nicht, und Änderungen der '
          'anderen kommen nicht mehr an. Wenn du dich wieder anmeldest, kommen '
          'die Gruppen neu dazu; die lokale Kopie bleibt getrennt davon '
          'bestehen.\n\n'
          'Entfernst du sie, bleiben sie für die anderen Mitglieder erhalten '
          'und kommen bei der nächsten Anmeldung zurück.'
          '${unsent ? '\n\nAchtung: Es gibt noch nicht übertragene '
                    'Änderungen. Sie erreichen die Gruppe nach dem Abmelden '
                    'nicht mehr.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Entfernen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lokal behalten'),
          ),
        ],
      ),
    );
    if (keep == null) return;
    await matrix.logout(keepGroups: keep);
  }

  Future<void> _deleteAccount(MatrixService matrix) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konto löschen'),
        content: Text(
          'Dein Matrix-Konto ${matrix.userId ?? ''} gehört zu deinem '
          'Matrix-Server, nicht zu Konsum. Gelöscht wird es auf der Seite des '
          'Servers, die sich jetzt im Browser öffnet.\n\n'
          'Damit verlierst du den Zugang zu allen geteilten Gruppen, auch in '
          'anderen Matrix-Programmen. Die Daten auf diesem Gerät bleiben, bis '
          'du die App deinstallierst.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zur Seite des Servers'),
          ),
        ],
      ),
    );
    if (ok == true) await matrix.openAccountDeletion();
  }

  Future<void> _recoveryKey(MatrixService matrix) async {
    final key = await promptText(
      context,
      title: 'Wiederherstellungsschlüssel',
      label: 'Schlüssel oder Sicherheits-Passphrase',
      confirm: 'Verifizieren',
    );
    if (key == null) return;
    if (await matrix.verifyWithRecoveryKey(key) && mounted) {
      AppScope.of(context).status.show('Dieses Gerät ist jetzt verifiziert');
    }
  }

  List<Widget> _serverStep(MatrixService matrix) => [
    const Text(
      'Mit einem Matrix-Konto lassen sich Gruppen mit anderen teilen '
      'und zwischen eigenen Geräten abgleichen.',
    ),
    const SizedBox(height: 16),
    TextField(
      controller: _server,
      autocorrect: false,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      decoration: const InputDecoration(
        labelText: 'Server oder Matrix-ID',
        hintText: 'matrix.org oder @name:matrix.org',
        border: OutlineInputBorder(),
      ),
      onSubmitted: matrix.busy ? null : (_) => _check(matrix),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: matrix.busy ? null : () => _check(matrix),
      child: const Text('Weiter'),
    ),
  ];

  List<Widget> _loginStep(MatrixService matrix, ServerLogin login) {
    final busy = matrix.busy;
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dns_outlined),
        title: Text(login.homeserver.host),
        trailing: TextButton(
          onPressed: busy ? null : () => setState(() => _login = null),
          child: const Text('Ändern'),
        ),
      ),
      if (login.browser) ...[
        const Text(
          'Anmeldung und Registrierung laufen auf der Webseite des Servers. '
          'Dein Passwort gibst du nur dort ein, Konsum bekommt es nicht zu '
          'sehen.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('Anmelden'),
          onPressed: busy ? null : () => matrix.loginWithBrowser(),
        ),
        if (login.canRegister) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Neues Konto erstellen'),
            onPressed: busy
                ? null
                : () => matrix.loginWithBrowser(register: true),
          ),
        ],
        if (login.password && !_showPassword)
          TextButton(
            onPressed: busy ? null : () => setState(() => _showPassword = true),
            child: const Text('Stattdessen mit Passwort anmelden'),
          ),
      ] else if (!matrix.browserLoginAvailable)
        const Text(
          'Im Browser geht nur die Anmeldung mit Passwort. Ein neues Konto '
          'legst du in der Android- oder Linux-App oder auf der Webseite '
          'des Servers an.',
        )
      else
        const Text(
          'Dieser Server bietet keine Registrierung aus Apps an. Ein neues '
          'Konto legst du auf der Webseite des Servers an.',
        ),
      if (_showPassword && login.password) ...[
        const SizedBox(height: 16),
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Benutzer oder Matrix-ID',
            hintText: '@name:beispiel.de',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passwort',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () => matrix.login(user: _user.text, password: _password.text),
          child: const Text('Mit Passwort anmelden'),
        ),
      ],
    ];
  }
}
