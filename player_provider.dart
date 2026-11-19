import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_model.dart';
import '../services/youtube_lyrics_service.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer audioPlayer = AudioPlayer();
  final YoutubeLyricsService _service = YoutubeLyricsService();

  SongModel? currentSong;
  List<SongModel> queue = [];
  int queueIndex = -1;
  List<LyricLine> lyrics = [];
  bool lyricsLoading = false;
  bool isLoadingStream = false;
  String? error;
  bool shuffle = false;
  bool repeat = false;

  List<SongModel> favorites = [];
  List<SongModel> recents = [];
  SharedPreferences? _prefs;

  Color dominantColor = const Color(0xFF2C2C2E);
  Color vibrantColor = const Color(0xFFFA2D48);
  int _token = 0;

  bool get isPlaying => audioPlayer.playing && error == null;

  PlayerProvider() {
    audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          !isLoadingStream) {
        if (repeat) {
          audioPlayer.seek(Duration.zero);
          audioPlayer.play();
        } else {
          next();
        }
      }
      notifyListeners();
    });
    _loadLibrary();
  }

  // ---------- library ----------
  Future<void> _loadLibrary() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      favorites = _decode(_prefs!.getString('favorites'));
      recents = _decode(_prefs!.getString('recents'));
      notifyListeners();
    } catch (_) {}
  }

  List<SongModel> _decode(String? s) {
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _save() {
    _prefs?.setString(
        'favorites', jsonEncode(favorites.map((s) => s.toJson()).toList()));
    _prefs?.setString(
        'recents', jsonEncode(recents.map((s) => s.toJson()).toList()));
  }

  bool isFavorite(String id) => favorites.any((s) => s.id == id);

  void toggleFavorite(SongModel song) {
    if (isFavorite(song.id)) {
      favorites.removeWhere((s) => s.id == song.id);
    } else {
      favorites.insert(0, song);
    }
    _save();
    notifyListeners();
  }

  void _addRecent(SongModel song) {
    recents.removeWhere((s) => s.id == song.id);
    recents.insert(0, song);
    if (recents.length > 30) recents.removeLast();
    _save();
  }

  // ---------- playback ----------
  Future<void> playSong(SongModel song, {List<SongModel>? newQueue}) async {
    if (newQueue != null) queue = newQueue;
    queueIndex = queue.indexWhere((s) => s.id == song.id);
    final token = ++_token;
    currentSong = song;
    isLoadingStream = true;
    error = null;
    lyrics = [];
    lyricsLoading = false;
    _addRecent(song);
    audioPlayer.stop();
    notifyListeners();

    _extractColors(song.artworkUrl);

    try {
      final file = await _service.downloadAudio(song.id);
      if (token != _token) return;
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.file(file.path),
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

      lyricsLoading = true;
      notifyListeners();
      final l = await _service.fetchSyncedLyrics(song.title, song.artist);
      if (token == _token) {
        lyrics = l;
        lyricsLoading = false;
        notifyListeners();
      }
    } catch (e) {
      if (token == _token) {
        isLoadingStream = false;
        var msg = e.toString().replaceAll('\n', ' ');
        if (msg.length > 90) msg = msg.substring(0, 90);
        error = 'Playback failed: $msg';
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
    if (error != null && currentSong != null) {
      playSong(currentSong!);
      return;
    }
    if (audioPlayer.playing) {
      audioPlayer.pause();
    } else {
      audioPlayer.play();
    }
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void toggleRepeat() {
    repeat = !repeat;
    notifyListeners();
  }

  void next() {
    if (queue.isEmpty || queueIndex < 0) return;
    if (shuffle && queue.length > 1) {
      int i;
      do {
        i = Random().nextInt(queue.length);
      } while (i == queueIndex);
      playSong(queue[i]);
    } else if (queueIndex + 1 < queue.length) {
      playSong(queue[queueIndex + 1]);
    }
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
