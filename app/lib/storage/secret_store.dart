import 'kwallet.dart';
import 'secret_service.dart';

/// Schlüsselbund des Desktops, in dem die App kleine Geheimnisse ablegt
/// (den Schlüssel der Matrix-Datenbank).
abstract interface class SecretStore {
  /// Für Meldungen, z. B. „KWallet“ oder „Schlüsselbund“.
  String get name;

  /// Das gespeicherte Geheimnis zu [key], null wenn es keines gibt.
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> close();
}

/// Öffnet den Schlüsselbund: zuerst KWallet (dort liegen die Schlüssel
/// bestehender Installationen), sonst den Secret Service (gnome-keyring,
/// KeePassXC, …). null, wenn keiner verfügbar ist.
Future<SecretStore?> openSecretStore() async =>
    await KWallet.open() ?? await SecretService.open();
