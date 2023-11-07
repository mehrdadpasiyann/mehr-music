import 'package:flutter/material.dart';

import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/youtube/pages/youtube_page.dart';
import 'package:namida/youtube/pages/yt_history_page.dart';
import 'package:namida/youtube/pages/yt_playlist_subpage.dart';

class YouTubeHomeView extends StatelessWidget {
  const YouTubeHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = [lang.HOME, lang.HISTORY, lang.MOST_PLAYED];
    const historyIndex = 1;
    return BackgroundWrapper(
      child: NamidaTabView(
        initialIndex: historyIndex,
        tabs: tabs,
        onIndexChanged: (index) {},
        children: const [
          YoutubePage(),
          YoutubeHistoryPage(),
          MostPlayedYTVideosPage(),
        ],
      ),
    );
  }
}
