import 'dart:convert';
import 'dart:io' show Directory, File;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';

class YoutubeLyricsService {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<SongModel>> searchSongs(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final searchList = await _yt.search.search(query);
      return searchList.take(15).map((video) {
        return SongModel(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          artworkUrl: video.thumbnails.highResUrl,
          duration: video.duration ?? const Duration(minutes: 3),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Downloads the audio to a cache file (most reliable way to play on Android)
  /// and returns it. Throws on failure.
  Future<File> downloadAudio(String videoId) async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/audio_cache');
    if (!await dir.exists()) await dir.create(recursive: true);

    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final audio = manifest.audioOnly;
    final mp4 = audio.where((s) => s.container == StreamContainer.mp4).toList();
    final AudioOnlyStreamInfo info;
    if (mp4.isNotEmpty) {
      mp4.sort((a, b) =>
          b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      info = mp4.first;
    } else {
      info = audio.withHighestBitrate();
    }

    final ext = info.container == StreamContainer.mp4 ? 'm4a' : 'webm';
    final file = File('${dir.path}/$videoId.$ext');
    if (await file.exists() && await file.length() > 0) return file;

    final part = File('${file.path}.part');
    final sink = part.openWrite();
    try {
      await sink.addStream(_yt.videos.streamsClient.get(info));
    } finally {
      await sink.close();
    }
    return part.rename(file.path);
  }

  Future<List<LyricLine>> fetchSyncedLyrics(String title, String artist) async {
    final cleanTitle =
        title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final cleanArtist = artist
        .replaceAll(RegExp(r'\s*-\s*Topic$|VEVO$', caseSensitive: false), '')
        .trim();

    try {
      final r = await http.get(Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      }));
      if (r.statusCode == 200) {
        final l = _fromJson(jsonDecode(r.body));
        if (l.isNotEmpty) return l;
      }
    } catch (_) {}

    try {
      final r = await http.get(Uri.https(
          'lrclib.net', '/api/search', {'q': '$cleanTitle $cleanArtist'}));
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
