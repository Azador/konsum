import 'package:flutter/material.dart';

import 'scope.dart';

/// Anmeldung am Matrix-Server.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
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
          ] else ...[
            const Text(
              'Mit einem Matrix-Konto lassen sich Gruppen mit anderen teilen '
              'und zwischen eigenen Geräten abgleichen.',
            ),
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
            const SizedBox(height: 12),
            TextField(
              controller: _server,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server (optional bei vollständiger Matrix-ID)',
                hintText: 'matrix.beispiel.de',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: matrix.busy
                  ? null
                  : () => matrix.login(
                      homeserver: _server.text,
                      user: _user.text,
                      password: _password.text,
                    ),
              child: const Text('Anmelden'),
            ),
          ],
          if (matrix.busy)
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
}
