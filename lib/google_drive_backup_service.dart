import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static final GoogleDriveBackupService instance = GoogleDriveBackupService._();
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const _scopes = <String>[drive.DriveApi.driveAppdataScope];
  static Future<void>? _initialization;

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get account => _account;

  Future<void> _initialize() =>
      _initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );

  Future<GoogleSignInAccount?> restoreSession() async {
    await _initialize();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (attempt == null) return null;
    _account = await attempt;
    return _account;
  }

  Future<GoogleSignInAccount> signIn() async {
    await _initialize();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw UnsupportedError(
        'Google-Anmeldung wird auf diesem Gerät nicht unterstützt.',
      );
    }
    _account = await GoogleSignIn.instance.authenticate();
    await _account!.authorizationClient.authorizeScopes(_scopes);
    return _account!;
  }

  Future<void> signOut() async {
    await _initialize();
    await GoogleSignIn.instance.signOut();
    _account = null;
  }

  Future<void> uploadBackup(String filePath) async {
    final api = await _driveApi(promptForAuthorization: true);
    final client = _activeClient!;
    try {
      final existingFiles = await api.files.list(
        spaces: 'appDataFolder',
        q: "name = 'bonkeepr_backup.zip' and trashed = false",
        pageSize: 10,
        orderBy: 'modifiedTime desc',
        $fields: 'files(id,name,modifiedTime)',
      );
      final previousFiles = existingFiles.files ?? const <drive.File>[];
      final previous = previousFiles.isEmpty ? null : previousFiles.first;
      final file = drive.File(name: 'bonkeepr_backup.zip');
      final media = drive.Media(
        _fileStream(filePath),
        await _fileLength(filePath),
        contentType: 'application/zip',
      );
      final previousId = previous?.id;
      if (previousId != null) {
        await api.files.update(file, previousId, uploadMedia: media);
      } else {
        file.parents = const ['appDataFolder'];
        await api.files.create(file, uploadMedia: media);
      }
    } finally {
      client.close();
      _activeClient = null;
    }
  }

  Future<Uint8List?> downloadLatestBackup() async {
    final api = await _driveApi(promptForAuthorization: true);
    final client = _activeClient!;
    try {
      final files = await api.files.list(
        spaces: 'appDataFolder',
        q: "name = 'bonkeepr_backup.zip' and trashed = false",
        pageSize: 1,
        orderBy: 'modifiedTime desc',
        $fields: 'files(id,name,modifiedTime)',
      );
      final latestFiles = files.files ?? const <drive.File>[];
      final id = latestFiles.isEmpty ? null : latestFiles.first.id;
      if (id == null) return null;
      final response = await api.files.get(
        id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (response is! drive.Media) {
        throw StateError('Google Drive hat keine Backup-Datei geliefert.');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
      _activeClient = null;
    }
  }

  _BearerAuthClient? _activeClient;

  Future<drive.DriveApi> _driveApi({
    required bool promptForAuthorization,
  }) async {
    await _initialize();
    final account = _account ?? await restoreSession();
    if (account == null) {
      throw StateError('Bitte zuerst Google Drive verbinden.');
    }
    final authClient = account.authorizationClient;
    final authorization =
        await authClient.authorizationForScopes(_scopes) ??
        (promptForAuthorization
            ? await authClient.authorizeScopes(_scopes)
            : null);
    if (authorization == null) {
      throw StateError(
        'Die Berechtigung für den privaten Google-Drive-Backupordner fehlt.',
      );
    }
    final client = _BearerAuthClient(authorization.accessToken);
    _activeClient = client;
    return drive.DriveApi(client);
  }

  Stream<List<int>> _fileStream(String filePath) => File(filePath).openRead();

  Future<int> _fileLength(String filePath) => File(filePath).length();
}

class _BearerAuthClient extends http.BaseClient {
  _BearerAuthClient(this._token);

  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

