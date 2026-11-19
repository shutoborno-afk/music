import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'models/song_model.dart';
import 'providers/player_provider.dart';
import 'screens/now_playing_screen.dart';
import 'services/youtube_lyrics_service.dart';

const Color kAccent = Color(0xFFFA2D48);
final YoutubeLyricsService appService = YoutubeLyricsService();

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
        primaryColor: kAccent,
      ),
      home: const MainTabShell(),
    );
  }
}

void playFrom(BuildContext context, SongModel song, List<SongModel> queue) {
  context.read<PlayerProvider>().playSong(song, newQueue: queue);
}

// ============================ SHELL ============================

class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key});

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          ListenNowTab(),
          BrowseTab(),
          RadioTab(),
          LibraryTab(),
          SearchTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: const Color(0xFF111111),
            selectedItemColor: kAccent,
            unselectedItemColor: Colors.white54,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.play_circle_fill),
                  label: 'Listen Now'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.square_grid_2x2_fill),
                  label: 'Browse'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.dot_radiowaves_left_right),
                  label: 'Radio'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.music_albums_fill),
                  label: 'Library'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.search), label: 'Search'),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================ SHARED WIDGETS ============================

class PageTitle extends StatelessWidget {
  final String text;
  const PageTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
      );
}

class SongTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  const SongTile({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SquareArt(url: song.artworkUrl, size: 52, radius: 6),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54)),
      onTap: onTap,
    );
  }
}

class SongShelf extends StatefulWidget {
  final String title;
  final String query;
  const SongShelf({super.key, required this.title, required this.query});

  @override
  State<SongShelf> createState() => _SongShelfState();
}

class _SongShelfState extends State<SongShelf> {
  static final Map<String, Future<List<SongModel>>> _cache = {};
  late Future<List<SongModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SongModel>> _load() {
    return _cache.putIfAbsent(widget.query, () {
      final f = appService.searchSongs(widget.query);
      // Never keep a failed request cached, or Retry would return the failure.
      f.catchError((_) {
        _cache.remove(widget.query);
        return <SongModel>[];
      });
      return f;
    });
  }

  void _retry() {
    _cache.remove(widget.query);
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(widget.title),
                const SizedBox(
                    height: 120,
                    child: Center(child: CupertinoActivityIndicator())),
              ],
            ),
          );
        }
        final songs = snap.data ?? [];
        if (songs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                    child: Text('${widget.title}: could not load',
                        style: const TextStyle(color: Colors.white54))),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        return ShelfRow(title: widget.title, songs: songs);
      },
    );
  }
}

Widget _header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    );

class ShelfRow extends StatelessWidget {
  final String title;
  final List<SongModel> songs;
  const ShelfRow({super.key, required this.title, required this.songs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(title),
        SizedBox(
          height: 235,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: songs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final s = songs[i];
              return GestureDetector(
                onTap: () => playFrom(context, s, songs),
                child: SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SquareArt(url: s.artworkUrl, size: 150, radius: 10),
                      const SizedBox(height: 8),
                      Text(s.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ============================ LISTEN NOW ============================

class ListenNowTab extends StatelessWidget {
  const ListenNowTab({super.key});

  static const shelves = <MapEntry<String, String>>[
    MapEntry('Top Hits', 'top hit songs 2026'),
    MapEntry('Trending Now', 'trending new songs'),
    MapEntry('Bangla Hits', 'bangla hit songs'),
    MapEntry('Chill Lofi', 'lofi chill songs'),
  ];

  @override
  Widget build(BuildContext context) {
    final recents = context.watch<PlayerProvider>().recents;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const PageTitle('Listen Now'),
          if (recents.isNotEmpty)
            ShelfRow(title: 'Recently Played', songs: recents),
          for (final e in shelves) SongShelf(title: e.key, query: e.value),
        ],
      ),
    );
  }
}

// ============================ BROWSE ============================

class BrowseTab extends StatelessWidget {
  const BrowseTab({super.key});

  static const genres = <(String, String, Color)>[
    ('Pop', 'pop hits songs', Color(0xFFFA2D48)),
    ('Hip-Hop', 'hip hop rap songs', Color(0xFFFF9500)),
    ('Rock', 'rock songs', Color(0xFF8E8E93)),
    ('Bangla', 'bangla songs', Color(0xFF34C759)),
    ('Bollywood', 'bollywood hit songs', Color(0xFFAF52DE)),
    ('Lo-fi', 'lofi beats', Color(0xFF5E5CE6)),
    ('Romantic', 'romantic love songs', Color(0xFFFF2D55)),
    ('Workout', 'workout gym music', Color(0xFFFF3B30)),
    ('Acoustic', 'acoustic songs', Color(0xFFA2845E)),
    ('EDM', 'edm dance music', Color(0xFF32ADE6)),
    ('Jazz', 'jazz music', Color(0xFFFFCC00)),
    ('Classical', 'classical music', Color(0xFF64D2FF)),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Browse'),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.7,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                for (final g in genres)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            CategoryPage(title: g.$1, query: g.$2))),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [g.$3, g.$3.withValues(alpha: 0.55)],
                        ),
                      ),
                      child: Text(g.$1,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryPage extends StatefulWidget {
  final String title;
  final String query;
  const CategoryPage({super.key, required this.title, required this.query});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  late Future<List<SongModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = appService.searchSongs(widget.query);
  }

  void _retry() =>
      setState(() => _future = appService.searchSongs(widget.query));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title), backgroundColor: Colors.black),
      bottomNavigationBar: const MiniPlayer(),
      body: FutureBuilder<List<SongModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator(radius: 14));
          }
          final songs = snap.data ?? [];
          if (songs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load songs',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kAccent),
                    onPressed: _retry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kAccent),
                  onPressed: () => playFrom(context, songs.first, songs),
                  icon: const Icon(CupertinoIcons.play_fill),
                  label: const Text('Play all'),
                ),
              ),
              for (final s in songs)
                SongTile(song: s, onTap: () => playFrom(context, s, songs)),
            ],
          );
        },
      ),
    );
  }
}

// ============================ RADIO ============================

class RadioTab extends StatelessWidget {
  const RadioTab({super.key});

  static const stations = <(String, String, String, IconData)>[
    ('Hits Radio', 'Today\'s biggest songs', 'top hits mix 2026', CupertinoIcons.flame_fill),
    ('Chill Radio', 'Relax and unwind', 'chill music mix', CupertinoIcons.moon_fill),
    ('Bangla Radio', 'Best of Bangla music', 'bangla songs mix', CupertinoIcons.music_note_2),
    ('Throwback Radio', 'Classics you love', 'throwback hits 2000s mix', CupertinoIcons.time),
    ('Focus Radio', 'Music for concentration', 'focus study music', CupertinoIcons.bolt_fill),
    ('Workout Radio', 'Energy for the gym', 'workout music mix', CupertinoIcons.heart_fill),
  ];

  Future<void> _start(BuildContext context, String title, String query) async {
    final player = context.read<PlayerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text('Starting $title…'),
        duration: const Duration(seconds: 2)));
    List<SongModel> songs;
    try {
      songs = await appService.searchSongs(query);
    } catch (_) {
      songs = [];
    }
    if (songs.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not load this station')));
      return;
    }
    songs.shuffle();
    player.playSong(songs.first, newQueue: songs);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Radio'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                for (final s in stations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _start(context, s.$1, s.$3),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: kAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(s.$4, color: Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.$1,
                                      style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600)),
                                  Text(s.$2,
                                      style: const TextStyle(
                                          color: Colors.white54)),
                                ],
                              ),
                            ),
                            const Icon(CupertinoIcons.play_circle,
                                color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ LIBRARY ============================

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  int _seg = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerProvider>();
    final list = _seg == 0 ? p.favorites : p.recents;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Library'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _seg,
                children: const {
                  0: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Favorites')),
                  1: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Recently Played')),
                },
                onValueChanged: (v) => setState(() => _seg = v ?? 0),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _seg == 0
                            ? 'Tap the heart in the player to add favorites'
                            : 'Songs you play will show up here',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => SongTile(
                      song: list[i],
                      onTap: () => playFrom(context, list[i], list),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================ SEARCH ============================

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _controller = TextEditingController();
  List<SongModel> _results = [];
  bool _isSearching = false;
  bool _searched = false;

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    List<SongModel> results;
    try {
      results = await appService.searchSongs(query);
    } catch (_) {
      results = [];
    }
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
          const PageTitle('Search'),
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
                        itemBuilder: (context, i) => SongTile(
                          song: _results[i],
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            playFrom(context, _results[i], _results);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================ MINI PLAYER ============================

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
            SquareArt(url: song.artworkUrl, size: 44, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                      p.error ??
                          (p.isLoadingStream
                              ? (p.loadProgress > 0
                                  ? 'Loading… ${(p.loadProgress * 100).round()}%'
                                  : 'Loading…')
                              : song.artist),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: p.error != null
                              ? Colors.redAccent
                              : Colors.white54)),
                ],
              ),
            ),
            p.isLoadingStream
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CupertinoActivityIndicator())
                : IconButton(
                    icon: Icon(p.isPlaying
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
