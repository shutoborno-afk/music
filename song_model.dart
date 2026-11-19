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
}

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});
}
