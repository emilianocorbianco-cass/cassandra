import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class StorageUploadResult {
  const StorageUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.uploaded,
  });

  final String downloadUrl;
  final String storagePath;
  final bool uploaded;
}

class _CacheEntry {
  _CacheEntry(this.bytes) : fetchedAt = DateTime.now();
  final Uint8List? bytes;
  final DateTime fetchedAt;
}

class StorageService {
  StorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const String _kStorageReferenceScheme = 'storage://';

  // ── In-memory byte cache ────────────────────────────────────────────────
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _maxCacheEntries = 50;

  // ── Download-URL cache (storage:// → HTTPS, never expires) ────────────
  static final Map<String, String> _downloadUrlCache = {};

  static bool isStorageReference(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith(_kStorageReferenceScheme);
  }

  static String toStorageReference(String path) {
    final cleaned = path.trim();
    if (cleaned.isEmpty) return '';
    return '$_kStorageReferenceScheme$cleaned';
  }

  static String? extractStoragePathFromReference(String value) {
    final trimmed = value.trim();
    if (!isStorageReference(trimmed)) return null;
    final path = trimmed.substring(_kStorageReferenceScheme.length).trim();
    return path.isEmpty ? null : path;
  }

  static String normalizePersistedReference(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    if (isStorageReference(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    final host = uri.host.toLowerCase();
    final isFirebaseHost =
        host == 'firebasestorage.googleapis.com' ||
        (host == 'storage.googleapis.com' && uri.path.contains('/o/'));
    if (!isFirebaseHost) return trimmed;

    final marker = '/o/';
    final idx = uri.path.indexOf(marker);
    if (idx < 0) return trimmed;
    final encoded = uri.path.substring(idx + marker.length).trim();
    if (encoded.isEmpty) return trimmed;
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      if (decoded.isEmpty) return trimmed;
      return toStorageReference(decoded);
    } catch (_) {
      return trimmed;
    }
  }

  bool isRemoteImageUrl(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  bool isDataImage(String value) {
    return value.trim().toLowerCase().startsWith('data:image/');
  }

  bool isFirebaseStorageUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !isRemoteImageUrl(trimmed)) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host == 'firebasestorage.googleapis.com') return true;
    if (host == 'storage.googleapis.com') return uri.path.contains('/o/');
    return false;
  }

  bool isStoragePathReference(String value) {
    return isStorageReference(value);
  }

  String storageReferenceFromPath(String path) {
    return toStorageReference(path);
  }

  String? storagePathFromReference(String value) {
    return extractStoragePathFromReference(value);
  }

  String? storagePathFromFirebaseStorageUrl(String value) {
    final trimmed = value.trim();
    if (!isFirebaseStorageUrl(trimmed)) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final path = uri.path;
    final marker = '/o/';
    final idx = path.indexOf(marker);
    if (idx < 0) return null;
    final encoded = path.substring(idx + marker.length).trim();
    if (encoded.isEmpty) return null;
    try {
      final decoded = Uri.decodeComponent(encoded);
      return decoded.trim().isEmpty ? null : decoded.trim();
    } catch (_) {
      return null;
    }
  }

  String normalizePersistedImageReference(String value) {
    return normalizePersistedReference(value);
  }

  Future<StorageUploadResult?> uploadUserProfileImage({
    required String uid,
    required String source,
  }) async {
    final payload = await _buildPayload(source);
    if (payload == null) {
      final cleaned = source.trim();
      if (isRemoteImageUrl(cleaned)) {
        return StorageUploadResult(
          downloadUrl: cleaned,
          storagePath: '',
          uploaded: false,
        );
      }
      return null;
    }

    final path =
        'users/$uid/profile/${DateTime.now().millisecondsSinceEpoch}'
        '.${payload.extension}';
    return _uploadPayload(path: path, payload: payload);
  }

  Future<StorageUploadResult?> uploadGroupImage({
    required String groupId,
    required String source,
  }) async {
    final payload = await _buildPayload(source);
    if (payload == null) {
      final cleaned = source.trim();
      if (isRemoteImageUrl(cleaned)) {
        return StorageUploadResult(
          downloadUrl: cleaned,
          storagePath: '',
          uploaded: false,
        );
      }
      return null;
    }

    final path =
        'groups/$groupId/images/${DateTime.now().millisecondsSinceEpoch}'
        '.${payload.extension}';
    return _uploadPayload(path: path, payload: payload);
  }

  Reference? _referenceFromAny(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final storagePath = storagePathFromReference(trimmed);
    if (storagePath != null && storagePath.isNotEmpty) {
      return _storage.ref(storagePath);
    }
    if (isFirebaseStorageUrl(trimmed)) {
      try {
        return _storage.refFromURL(trimmed);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<Uint8List?> readBytesByReference(
    String reference, {
    int maxSizeBytes = 2 * 1024 * 1024,
  }) async {
    final key = reference.trim();
    if (key.isEmpty) return null;

    // Check cache first.
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.bytes;
    }

    final ref = _referenceFromAny(reference);
    if (ref == null) return null;
    try {
      final bytes = await ref.getData(maxSizeBytes).timeout(_requestTimeout);
      _putCache(key, bytes);
      return bytes;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found' || e.code == 'unauthorized') {
        _putCache(key, null);
        return null;
      }
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static void _putCache(String key, Uint8List? bytes) {
    // Evict oldest entries when cache is full.
    if (_cache.length >= _maxCacheEntries && !_cache.containsKey(key)) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.fetchedAt.isBefore(b.value.fetchedAt) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry(bytes);
  }

  /// Synchronous byte-cache lookup. Returns cached bytes if available
  /// and not expired, or null without triggering any network request.
  static Uint8List? getCachedBytes(String reference) {
    final key = reference.trim();
    if (key.isEmpty) return null;
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.bytes;
    }
    return null;
  }

  /// Resolve a storage:// reference to an HTTPS download URL.
  /// The mapping is cached permanently in memory.
  Future<String?> getDownloadUrl(String reference) async {
    final key = reference.trim();
    if (key.isEmpty) return null;
    final cached = _downloadUrlCache[key];
    if (cached != null) return cached;
    final ref = _referenceFromAny(reference);
    if (ref == null) return null;
    try {
      final url = await ref.getDownloadURL().timeout(_requestTimeout);
      _downloadUrlCache[key] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Seed the download-URL cache (e.g. right after uploading).
  static void seedDownloadUrlCache(String reference, String downloadUrl) {
    final key = reference.trim();
    if (key.isNotEmpty && downloadUrl.isNotEmpty) {
      _downloadUrlCache[key] = downloadUrl;
    }
  }

  /// Evict a specific reference from the cache (e.g. after upload/delete).
  static void evictCache(String reference) {
    _cache.remove(reference.trim());
    _downloadUrlCache.remove(reference.trim());
  }

  /// Clear the entire byte cache.
  static void clearCache() {
    _cache.clear();
    _downloadUrlCache.clear();
  }

  Future<void> deleteByDownloadUrl(String? downloadUrl) async {
    final cleaned = (downloadUrl ?? '').trim();
    final ref = _referenceFromAny(cleaned);
    if (ref == null) return;
    try {
      await ref.delete().timeout(_requestTimeout);
      evictCache(cleaned);
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }

  Future<bool> objectExistsByDownloadUrl(String downloadUrl) async {
    final ref = _referenceFromAny(downloadUrl);
    if (ref == null) return true;
    try {
      await ref.getMetadata().timeout(_requestTimeout);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return false;
      return true;
    } on TimeoutException {
      return true;
    }
  }

  Future<StorageUploadResult> _uploadPayload({
    required String path,
    required _UploadPayload payload,
  }) async {
    final ref = _storage.ref(path);
    final task = await ref
        .putData(payload.bytes, SettableMetadata(contentType: payload.mimeType))
        .timeout(_requestTimeout);
    final url = await task.ref.getDownloadURL().timeout(_requestTimeout);
    // Seed caches so the just-uploaded image is available instantly.
    final storageRef = toStorageReference(path);
    _putCache(storageRef, payload.bytes);
    seedDownloadUrlCache(storageRef, url);
    return StorageUploadResult(
      downloadUrl: url,
      storagePath: path,
      uploaded: true,
    );
  }

  Future<_UploadPayload?> _buildPayload(String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return null;
    }

    if (isDataImage(trimmed)) {
      final parsed = _decodeDataImage(trimmed);
      if (parsed == null) return null;
      return parsed;
    }

    var filePath = trimmed;
    if (lower.startsWith('file://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.scheme == 'file') {
        filePath = uri.toFilePath();
      } else {
        filePath = trimmed.replaceFirst(RegExp(r'^file://'), '');
      }
    }

    final file = File(filePath);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final mime = _mimeTypeForPath(file.path);
    final ext = _extensionForMime(mime);
    return _UploadPayload(bytes: bytes, mimeType: mime, extension: ext);
  }

  _UploadPayload? _decodeDataImage(String source) {
    final comma = source.indexOf(',');
    if (comma <= 0 || comma >= source.length - 1) return null;
    final header = source.substring(0, comma).toLowerCase();
    final body = source.substring(comma + 1).trim();
    if (body.isEmpty) return null;
    if (!header.contains(';base64')) return null;
    final mime = _mimeTypeFromDataHeader(header);
    if (mime == null) return null;
    try {
      final bytes = base64Decode(body);
      if (bytes.isEmpty) return null;
      return _UploadPayload(
        bytes: bytes,
        mimeType: mime,
        extension: _extensionForMime(mime),
      );
    } catch (_) {
      return null;
    }
  }

  String? _mimeTypeFromDataHeader(String header) {
    // Example: data:image/png;base64
    final prefix = 'data:';
    if (!header.startsWith(prefix)) return null;
    final semi = header.indexOf(';');
    if (semi <= prefix.length) return null;
    final mime = header.substring(prefix.length, semi).trim();
    if (!mime.startsWith('image/')) return null;
    return mime;
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  String _extensionForMime(String mime) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
      default:
        return 'jpg';
    }
  }
}

class _UploadPayload {
  const _UploadPayload({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;
}
