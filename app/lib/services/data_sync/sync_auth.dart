import 'dart:convert';

import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/sync_models.dart';

/// Builds outbound auth headers for a destination, reading the secret value
/// from secure storage via [DataSyncRepository]. Secrets are never logged or
/// persisted outside secure storage.
class SyncAuth {
  const SyncAuth(this._repo);

  final DataSyncRepository _repo;

  Future<Map<String, String>> headersFor(SyncDestination dest) async {
    switch (dest.authType) {
      case SyncAuthType.none:
        return const {};
      case SyncAuthType.apiKey:
        final secret = await _repo.getDestinationSecret(dest);
        if (secret == null || secret.isEmpty) return const {};
        final header = (dest.authHeaderName ?? '').trim();
        return {header.isEmpty ? 'X-API-Key' : header: secret};
      case SyncAuthType.bearer:
        final secret = await _repo.getDestinationSecret(dest);
        if (secret == null || secret.isEmpty) return const {};
        return {'Authorization': 'Bearer $secret'};
      case SyncAuthType.basic:
        final secret = await _repo.getDestinationSecret(dest) ?? '';
        final username = dest.authUsername ?? '';
        final token = base64Encode(utf8.encode('$username:$secret'));
        return {'Authorization': 'Basic $token'};
    }
  }
}
