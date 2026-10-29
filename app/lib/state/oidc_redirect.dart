import 'oidc_redirect_stub.dart'
    if (dart.library.io) 'oidc_redirect_io.dart'
    as impl;

/// Rückweg vom Browser in die App nach der Anmeldung auf der Webseite des
/// Servers.
abstract interface class OidcRedirect {
  /// Adresse, auf die der Server nach der Anmeldung umleitet.
  Uri get redirectUri;

  /// Wartet auf die Rückkehr aus dem Browser und liefert die vollständige
  /// Rücksprung-Adresse (mit `code` und `state`).
  Future<Uri> wait();

  Future<void> close();
}

/// Öffnet den Rückweg für diese Plattform, oder null, wenn die Anmeldung über
/// den Browser hier (noch) nicht geht.
Future<OidcRedirect?> openOidcRedirect() => impl.openOidcRedirect();
