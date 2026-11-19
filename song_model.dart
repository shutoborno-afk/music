class SongModel {
  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final Duration duration;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': duration.inMilliseconds,
      };

  factory SongModel.fromJson(Map<String, dynamic> j) => SongModel(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String,
        artworkUrl: j['artworkUrl'] as String,
        duration: Duration(milliseconds: (j['durationMs'] as int?) ?? 180000),
      );
}

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});
}
