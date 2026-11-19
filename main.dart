import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'models/song_model.dart';
import 'providers/player_provider.dart';
import 'screens/now_playing_screen.dart';
import 'services/youtube_lyrics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.applemusic.clone.channel.audio',
    androidNotificationChannelName: 'Music Playback',
    androidNotificationOngoing: true,
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerProvider(),
      child: const AppleMusicCloneApp(),
    ),
  );
}

class AppleMusicCloneApp extends StatelessWidget {
  const AppleMusicCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apple Music Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFFFA2D48),
      ),
      home: const MainTabShell(),
    );
  }
}

class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key});

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  int _selectedIndex = 4;

  static const _titles = ['Listen Now', 'Browse', 'Radio', 'Library'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (final t in _titles) _Placeholder(title: t),
          const SearchTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: const Color(0xFF111111),
            selectedItemColor: const Color(0xFFFA2D48),
            unselectedItemColor: Colors.white54,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.play_circle_fill), label: 'Listen Now'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.square_grid_2x2_fill), label: 'Browse'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.dot_radiowaves_left_right),
                  label: 'Radio'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.music_albums_fill), label: 'Library'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.search), label: 'Search'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            const Expanded(
              child: Center(
                child: Text('Use the Search tab to find and play songs',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final YoutubeLyricsService _service = YoutubeLyricsService();
  final TextEditingController _controller = TextEditingController();
  List<SongModel> _results = [];
  bool _isSearching = false;
  bool _searched = false;

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    final results = await _service.searchSongs(query);
    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
        _searched = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text('Search',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CupertinoSearchTextField(
              controller: _controller,
              placeholder: 'Songs, artists, lyrics',
              style: const TextStyle(color: Colors.white),
              onSubmitted: _performSearch,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isSearching
                ? const Center(child: CupertinoActivityIndicator(radius: 14))
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searched ? 'No results' : 'Search for a song to start',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final s = _results[i];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: s.artworkUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: Icon(Icons.music_note)),
                              ),
                            ),
                            title: Text(s.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(s.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54)),
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              context
                                  .read<PlayerProvider>()
                                  .playSong(s, newQueue: _results);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerProvider>();
    final song = p.currentSong;
    if (song == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(
            fullscreenDialog: true, builder: (_) => const NowPlayingScreen()),
      ),
      child: Container(
        height: 64,
        color: const Color(0xFF1C1C1E),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: song.artworkUrl,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const SizedBox(width: 44, height: 44),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(p.error ?? song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: p.error != null ? Colors.redAccent : Colors.white54)),
                ],
              ),
            ),
            p.isLoadingStream
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CupertinoActivityIndicator())
                : IconButton(
                    icon: Icon(p.audioPlayer.playing
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill),
                    onPressed: p.togglePlay,
                  ),
            IconButton(
              icon: const Icon(CupertinoIcons.forward_fill),
              onPressed: p.next,
            ),
          ],
        ),
      ),
    );
  }
}
