import 'package:flutter/material.dart';

import '../state/matrix_service.dart';
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
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Abmelden'),
              onPressed: matrix.busy ? null : matrix.logout,
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
