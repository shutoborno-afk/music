import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemEntity;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';

/// Thrown when audio can't be fetched; message is safe to show to the user.
class AudioFetchException implements Exception {
  final String message;
  AudioFetchException(this.message);
  @override
  String toString() => message;
}

class YoutubeLyricsService {
  // Single shared instance so the whole app reuses one YouTube client.
  static final YoutubeLyricsService _instance = YoutubeLyricsService._();
  factory YoutubeLyricsService() => _instance;
  YoutubeLyricsService._();

  YoutubeExplode _yt = YoutubeExplode();

  // Limit concurrent searches (the home screen fires several at once, and
  // YouTube rate-limits bursts, which made some categories fail to load).
  int _activeSearches = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> _acquire() async {
    if (_activeSearches < 2) {
      _activeSearches++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _activeSearches--;
    }
  }

  void _resetClient() {
    try {
      _yt.close();
    } catch (_) {}
    _yt = YoutubeExplode();
  }

  // ---------------------------------------------------------------- search

  /// Searches YouTube. Retries transient failures. Returns an empty list only
  /// when nothing was found; throws if every attempt failed (so the UI can
  /// show a Retry button instead of a silent blank).
  Future<List<SongModel>> searchSongs(String query) async {
    if (query.trim().isEmpty) return [];
    await _acquire();
    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final results = await _yt.search
              .search(query, filter: TypeFilters.video)
              .timeout(const Duration(seconds: 15));
          var videos = results.where((v) => !v.isLive).toList();
          // Prefer track-length videos; fall back to everything if too strict.
          final tracks = videos.where((v) {
            final d = v.duration;
            return d == null || (d.inSeconds >= 30 && d.inMinutes <= 20);
          }).toList();
          if (tracks.isNotEmpty) videos = tracks;
          final songs = videos
              .take(15)
              .map((video) => SongModel(
                    id: video.id.value,
                    title: video.title,
                    artist: video.author,
                    artworkUrl: video.thumbnails.highResUrl,
                    duration: video.duration ?? const Duration(minutes: 3),
                  ))
              .toList();
          if (songs.isNotEmpty) return songs;
          lastError = 'No results';
        } catch (e) {
          lastError = e;
          if (attempt == 1) _resetClient();
        }
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
      throw AudioFetchException('Search failed: $lastError');
    } finally {
      _release();
    }
  }

  // ----------------------------------------------------------------- audio

  Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/audio_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Keeps the cache small (newest 40 files).
  Future<void> _trimCache(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      if (files.length <= 40) return;
      final stats = <File, DateTime>{};
      for (final f in files) {
        stats[f] = (await f.stat()).modified;
      }
      files.sort((a, b) => stats[a]!.compareTo(stats[b]!));
      for (final f in files.take(files.length - 40)) {
        await _safeDelete(f);
      }
    } catch (_) {}
  }

  Future<void> _safeDelete(FileSystemEntity f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Returns a cached/downloaded audio file for [videoId].
  /// Tries several YouTube client profiles (some get 403/throttled), with a
  /// stall timeout so it can never hang on "Loading…" forever.
  /// [onProgress] receives 0..1.
  Future<File> downloadAudio(String videoId,
      {void Function(double progress)? onProgress}) async {
    final dir = await _cacheDir();

    // Already cached?
    for (final ext in const ['m4a', 'webm']) {
      final f = File('${dir.path}/$videoId.$ext');
      if (await f.exists() && await f.length() > 1024) return f;
    }

    final clientSets = <List<YoutubeApiClient>?>[
      [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
      [YoutubeApiClient.androidVr],
      null, // library defaults
    ];

    Object? lastError;
    for (var i = 0; i < clientSets.length; i++) {
      try {
        final file = await _tryDownload(dir, videoId, clientSets[i], onProgress);
        unawaited(_trimCache(dir));
        return file;
      } catch (e) {
        lastError = e;
        if (i == 0) _resetClient();
      }
    }
    throw AudioFetchException('Could not load audio ($lastError)');
  }

  Future<File> _tryDownload(Directory dir, String videoId,
      List<YoutubeApiClient>? clients,
      void Function(double)? onProgress) async {
    final manifest = await _yt.videos.streams
        .getManifest(videoId, ytClients: clients)
        .timeout(const Duration(seconds: 20));

    final audio = manifest.audioOnly.toList();
    if (audio.isEmpty) throw AudioFetchException('No audio streams');

    // Prefer m4a/aac (ExoPlayer plays it everywhere), highest bitrate.
    final mp4 = audio.where((s) => s.container == StreamContainer.mp4).toList();
    final pool = mp4.isNotEmpty ? mp4 : audio;
    pool.sort(
        (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    // A mid-quality stream downloads noticeably faster with no audible
    // difference on a phone: pick the best one at or under ~160 kbps.
    final info = pool.firstWhere(
        (s) => s.bitrate.bitsPerSecond <= 160000,
        orElse: () => pool.last);

    final ext = info.container == StreamContainer.mp4 ? 'm4a' : 'webm';
    final file = File('${dir.path}/$videoId.$ext');
    final part = File('${file.path}.part');
    await _safeDelete(part);

    final total = info.size.totalBytes;
    var received = 0;
    final sink = part.openWrite();
    try {
      final stream = _yt.videos.streams.get(info).timeout(
            const Duration(seconds: 15),
            onTimeout: (s) => s.addError(
                TimeoutException('Download stalled'), StackTrace.current),
          );
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } catch (_) {
      await sink.close().catchError((_) {});
      await _safeDelete(part);
      rethrow;
    }
    await sink.close();
    if (received < 1024) {
      await _safeDelete(part);
      throw AudioFetchException('Empty download');
    }
    return part.rename(file.path);
  }

  // ---------------------------------------------------------------- lyrics

  Future<List<LyricLine>> fetchSyncedLyrics(String title, String artist) async {
    final cleanTitle = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final cleanArtist = artist
        .replaceAll(RegExp(r'\s*-\s*Topic$|VEVO$', caseSensitive: false), '')
        .trim();

    try {
      final r = await http.get(Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      })).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final l = _fromJson(jsonDecode(r.body));
        if (l.isNotEmpty) return l;
      }
    } catch (_) {}

    try {
      final r = await http
          .get(Uri.https(
              'lrclib.net', '/api/search', {'q': '$cleanTitle $cleanArtist'}))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body);
        if (list is List) {
          for (final item in list) {
            final l = _fromJson(item);
            if (l.isNotEmpty) return l;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  List<LyricLine> _fromJson(dynamic data) {
    if (data is! Map) return [];
    final synced = data['syncedLyrics'];
    if (synced is String && synced.isNotEmpty) return _parseLrc(synced);
    return [];
  }

  List<LyricLine> _parseLrc(String lrc) {
    final List<LyricLine> lines = [];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (final line in lrc.split('\n')) {
      final m = regex.firstMatch(line.trim());
      if (m == null) continue;
      final mins = int.parse(m.group(1)!);
      final secs = int.parse(m.group(2)!);
      final frac = m.group(3)!;
      final ms = frac.length == 2 ? int.parse(frac) * 10 : int.parse(frac);
      lines.add(LyricLine(
        timestamp: Duration(minutes: mins, seconds: secs, milliseconds: ms),
        text: m.group(4)!.trim(),
      ));
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }
}
