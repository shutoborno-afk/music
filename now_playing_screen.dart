import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../providers/player_provider.dart';

/// Square artwork cropped from a YouTube thumbnail (removes the black bars).
class SquareArt extends StatelessWidget {
  final String url;
  final double? size;
  final double radius;
  const SquareArt({super.key, required this.url, this.size, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final core = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: FittedBox(
        fit: BoxFit.cover,
        child: ClipRect(
          child: Align(
            alignment: Alignment.center,
            widthFactor: 0.5625,
            heightFactor: 0.75,
            child: CachedNetworkImage(
              imageUrl: url,
              width: 480,
              height: 360,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox(
                  width: 480,
                  height: 360,
                  child: Icon(Icons.music_note, size: 120)),
            ),
          ),
        ),
      ),
    );
    if (size != null) return SizedBox(width: size, height: size, child: core);
    return AspectRatio(aspectRatio: 1, child: core);
  }
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  static const double _lineH = 76;
  static const double _padV = 120;
  bool _showLyrics = false;
  double? _drag;
  int _lastIndex = -2;
  String? _lastSongId;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final mins = d.inMinutes.toString();
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  int _currentLine(List<LyricLine> l, Duration pos) {
    int idx = -1;
    for (int i = 0; i < l.length; i++) {
      if (l[i].timestamp <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _scrollTo(int idx) {
    if (!_scroll.hasClients) return;
    final vp = _scroll.position.viewportDimension;
    final target =
        (_padV + (idx < 0 ? 0 : idx) * _lineH) - vp / 3 + _lineH / 2;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerProvider>();
    final song = p.currentSong;
    if (song == null) return const SizedBox.shrink();
    if (_lastSongId != song.id) {
      _lastSongId = song.id;
      _lastIndex = -2;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    p.vibrantColor.withValues(alpha: 0.75),
                    p.dominantColor,
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                child: Container(color: Colors.black.withValues(alpha: 0.2)),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_down,
                        color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _showLyrics
                          ? KeyedSubtree(
                              key: const ValueKey('lyrics'),
                              child: _lyricsView(p))
                          : KeyedSubtree(
                              key: const ValueKey('art'),
                              child: _artwork(p, song)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _titleRow(p, song),
                  if (p.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(p.error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
                    ),
                  const SizedBox(height: 4),
                  _seekBar(p, song),
                  _controls(p),
                  const SizedBox(height: 4),
                  _volumeBar(p),
                  _bottomBar(p),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleRow(PlayerProvider p, SongModel song) {
    final fav = p.isFavorite(song.id);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text(song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, color: Colors.white60)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(fav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              color: fav ? const Color(0xFFFA2D48) : Colors.white70),
          onPressed: () => p.toggleFavorite(song),
        ),
      ],
    );
  }

  Widget _artwork(PlayerProvider p, SongModel song) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedScale(
          scale: p.isPlaying ? 1.0 : 0.86,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54, blurRadius: 30, offset: Offset(0, 14))
              ],
            ),
            child: SquareArt(url: song.artworkUrl, radius: 14),
          ),
        ),
      ),
    );
  }

  Widget _lyricsView(PlayerProvider p) {
    if (p.lyrics.isEmpty) {
      return Center(
        child: Text(
          p.isLoadingStream || p.lyricsLoading
              ? 'Loading lyrics…'
              : 'No synced lyrics found',
          style: const TextStyle(color: Colors.white60, fontSize: 18),
        ),
      );
    }
    return StreamBuilder<Duration>(
      stream: p.audioPlayer.positionStream,
      builder: (context, snap) {
        final idx = _currentLine(p.lyrics, snap.data ?? Duration.zero);
        if (idx != _lastIndex) {
          _lastIndex = idx;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(idx));
        }
        return ListView.builder(
          controller: _scroll,
          itemExtent: _lineH,
          padding: const EdgeInsets.symmetric(vertical: _padV),
          itemCount: p.lyrics.length,
          itemBuilder: (context, i) {
            final line = p.lyrics[i];
            final active = i == idx;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => p.seek(line.timestamp),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: active ? 1.0 : 0.35,
                  child: Text(
                    line.text.isEmpty ? '♪' : line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _seekBar(PlayerProvider p, SongModel song) {
    return StreamBuilder<Duration>(
      stream: p.audioPlayer.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final total = p.audioPlayer.duration ?? song.duration;
        final maxMs =
            total.inMilliseconds < 1 ? 1.0 : total.inMilliseconds.toDouble();
        final value =
            (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs).toDouble();
        final shown = Duration(milliseconds: value.round());
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value,
                max: maxMs,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  p.seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(shown),
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
                Text('-${_fmt(total - shown)}',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _volumeBar(PlayerProvider p) {
    final icon = p.isMuted
        ? CupertinoIcons.speaker_slash_fill
        : p.volume < 0.5
            ? CupertinoIcons.speaker_1_fill
            : CupertinoIcons.speaker_2_fill;
    return Row(
      children: [
        IconButton(
          iconSize: 20,
          color: Colors.white60,
          icon: Icon(icon),
          onPressed: p.toggleMute,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: p.volume,
              min: 0,
              max: 1,
              // Apply live while dragging, save to prefs only when released.
              onChanged: (v) => p.setVolume(v, persist: false),
              onChangeEnd: (v) => p.setVolume(v),
            ),
          ),
        ),
        const Icon(CupertinoIcons.speaker_3_fill,
            size: 20, color: Colors.white60),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _controls(PlayerProvider p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 40,
          color: Colors.white,
          icon: const Icon(CupertinoIcons.backward_fill),
          onPressed: p.previous,
        ),
        p.isLoadingStream
            ? SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const CupertinoActivityIndicator(
                        radius: 16, color: Colors.white),
                    if (p.loadProgress > 0)
                      Positioned(
                        bottom: 0,
                        child: Text('${(p.loadProgress * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11)),
                      ),
                  ],
                ))
            : IconButton(
                iconSize: 64,
                color: Colors.white,
                icon: Icon(p.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill),
                onPressed: p.togglePlay,
              ),
        IconButton(
          iconSize: 40,
          color: Colors.white,
          icon: const Icon(CupertinoIcons.forward_fill),
          onPressed: p.next,
        ),
      ],
    );
  }

  Widget _bottomBar(PlayerProvider p) {
    Color c(bool on) => on ? Colors.white : Colors.white38;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 24,
          color: c(p.shuffle),
          icon: const Icon(CupertinoIcons.shuffle),
          onPressed: p.toggleShuffle,
        ),
        IconButton(
          iconSize: 26,
          color: c(_showLyrics),
          icon: Icon(_showLyrics
              ? CupertinoIcons.quote_bubble_fill
              : CupertinoIcons.quote_bubble),
          onPressed: () => setState(() => _showLyrics = !_showLyrics),
        ),
        IconButton(
          iconSize: 24,
          color: c(p.repeat),
          icon: const Icon(CupertinoIcons.repeat),
          onPressed: p.toggleRepeat,
        ),
      ],
    );
  }
}
