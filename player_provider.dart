import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/song_model.dart';
import '../services/youtube_lyrics_service.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer audioPlayer = AudioPlayer();
  final YoutubeLyricsService _service = YoutubeLyricsService();

  SongModel? currentSong;
  List<SongModel> queue = [];
  int queueIndex = -1;
  List<LyricLine> lyrics = [];
  bool isLoadingStream = false;
  String? error;

  Color dominantColor = const Color(0xFF2C2C2E);
  Color vibrantColor = const Color(0xFFFA2D48);
  int _token = 0;

  PlayerProvider() {
    audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          !isLoadingStream) {
        next();
      }
      notifyListeners();
    });
  }

  Future<void> playSong(SongModel song, {List<SongModel>? newQueue}) async {
    if (newQueue != null) queue = newQueue;
    queueIndex = queue.indexWhere((s) => s.id == song.id);
    final token = ++_token;
    currentSong = song;
    isLoadingStream = true;
    error = null;
    lyrics = [];
    notifyListeners();

    _extractColors(song.artworkUrl);

    final streamUrl = await _service.getAudioStreamUrl(song.id);
    if (token != _token) return;
    if (streamUrl == null) {
      isLoadingStream = false;
      error = 'Could not load audio stream';
      notifyListeners();
      return;
    }

    try {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(streamUrl),
          tag: MediaItem(
            id: song.id,
            album: 'Apple Music Clone',
            title: song.title,
            artist: song.artist,
            artUri: Uri.parse(song.artworkUrl),
          ),
        ),
      );
      if (token != _token) return;
      isLoadingStream = false;
      notifyListeners();
      audioPlayer.play();
      final l = await _service.fetchSyncedLyrics(song.title, song.artist);
      if (token == _token) {
        lyrics = l;
        notifyListeners();
      }
    } catch (_) {
      if (token == _token) {
        isLoadingStream = false;
        error = 'Playback failed';
        notifyListeners();
      }
    }
  }

  Future<void> _extractColors(String url) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        size: const Size(120, 120),
        maximumColorCount: 12,
      );
      vibrantColor = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          vibrantColor;
      dominantColor = palette.darkMutedColor?.color ??
          palette.dominantColor?.color ??
          dominantColor;
      notifyListeners();
    } catch (_) {}
  }

  void togglePlay() {
    if (audioPlayer.playing) {
      audioPlayer.pause();
    } else {
      audioPlayer.play();
    }
    notifyListeners();
  }

  void next() {
    if (queue.isEmpty || queueIndex < 0) return;
    if (queueIndex + 1 < queue.length) playSong(queue[queueIndex + 1]);
  }

  void previous() {
    if (audioPlayer.position > const Duration(seconds: 3)) {
      audioPlayer.seek(Duration.zero);
    } else if (queueIndex > 0) {
      playSong(queue[queueIndex - 1]);
    }
  }

  void seek(Duration d) => audioPlayer.seek(d);

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }
}
