// lib/screens/profile_screen.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:provider/provider.dart';
import 'package:characters/characters.dart';

// app
import 'package:booka_app/constants.dart';
import 'package:booka_app/widgets/current_listen_card.dart';
import 'package:booka_app/user_notifier.dart';
import 'package:booka_app/screens/login_screen.dart';
import 'package:booka_app/providers/audio_player_provider.dart';
import 'package:booka_app/screens/book_detail_screen.dart';
import 'package:booka_app/widgets/custom_bottom_nav_bar.dart';
import 'package:booka_app/screens/main_screen.dart';
import 'package:booka_app/screens/full_books_grid_screen.dart';
import 'package:booka_app/widgets/booka_app_bar.dart';
import 'package:booka_app/models/book.dart';
import 'package:booka_app/widgets/loading_indicator.dart';
// ⬇️(используем готовый бейдж минут)
import 'package:booka_app/widgets/minutes_badge.dart';
// ⛑ Безпечні тексти помилок (санітизація)
import 'package:booka_app/core/security/safe_errors.dart';
/// ✅ єдина точка завантаження профілю (тепер повертає Map)
import 'package:booka_app/repositories/profile_repository.dart';
// 🔗 для verify після покупки
import 'package:booka_app/core/network/api_client.dart';
// Billing (встроенный флоу Google Play)
import 'package:in_app_purchase/in_app_purchase.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>?> profileFuture;

  @override
  void initState() {
    super.initState();
    debugPrint('Profile: initState');
    profileFuture = _fetchUserProfile();

    // локал-first: тягнемо сервер лише якщо немає локальної сесії
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ap = context.read<AudioPlayerProvider>();
      final hasLocal = await ap.hasSavedSession();
      debugPrint('Profile: postFrame hasLocalSession=$hasLocal');
      if (!hasLocal) {
        await ap.hydrateFromServerIfAvailable();
      }
    });
  }

  Future<Map<String, dynamic>?> _fetchUserProfile({bool force = false}) async {
    try {
      debugPrint('Profile: load profile (force=$force)');
      return await ProfileRepository.I.loadMap(
        force: force,
        debugTag: 'ProfileScreen.load',
      );
    } catch (e) {
      debugPrint('Profile: load profile error: $e');
      return null;
    }
  }

  Future<void> _refresh() async {
    debugPrint('Profile: pull-to-refresh');
    final audio = context.read<AudioPlayerProvider>();
    final futProfile = _fetchUserProfile(force: true);

    // локал-first при оновленні
    final hasLocal = await audio.hasSavedSession();
    final futHydrate = hasLocal ? Future.value(false) : audio.hydrateFromServerIfAvailable();

    setState(() => profileFuture = futProfile);
    await Future.wait([futProfile, futHydrate]);
  }

  Future<void> logout(BuildContext context) async {
    debugPrint('Profile: logout');
    await Provider.of<UserNotifier>(context, listen: false).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  Future<void> _continueListening() async {
    final ap = context.read<AudioPlayerProvider>();

    // 1) спершу пробуємо підготуватися з локалі (миттєво)
    await ap.ensurePrepared();
    if (ap.currentBook != null && ap.currentChapter != null) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: ap.currentBook!,
            initialChapter: ap.currentChapter!,
            initialPosition: ap.position.inSeconds,
            autoPlay: true,
          ),
        ),
      );
      return;
    }

    // 2) локалі немає → пробуємо сервер
    final ok = await ap.hydrateFromServerIfAvailable();
    if (ok && ap.currentBook != null && ap.currentChapter != null) {
      await ap.ensurePrepared();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: ap.currentBook!,
            initialChapter: ap.currentChapter!,
            initialPosition: ap.position.inSeconds,
            autoPlay: true,
          ),
        ),
      );
      return;
    }

    // 3) нічого не знайшли
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Немає поточного прослуховування')),
    );
  }

  Future<void> _openPlayer() async {
    final ap = context.read<AudioPlayerProvider>();
    final book = ap.currentBook;
    final chapter = ap.currentChapter;
    if (book != null && chapter != null) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: book,
            initialChapter: chapter,
            initialPosition: ap.position.inSeconds,
            autoPlay: false,
          ),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Немає поточного прослуховування')),
      );
    }
  }

  void _switchMainTabAndClose(int tab) {
    final ms = MainScreen.of(context);
    if (ms != null) {
      ms.setTab(tab);
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainScreen(initialIndex: tab)),
            (route) => false,
      );
    }
  }

  /// Нижній бар: 0=Жанри (CatalogAndCollections), 1=Каталог, 2=Плеєр, 3=Профіль
  void _onBottomTab(int index) {
    switch (index) {
      case 0:
        _switchMainTabAndClose(0);
        break;
      case 1:
        _switchMainTabAndClose(1);
        break;
      case 2:
        _openPlayer();
        break;
      case 3:
        break;
    }
  }

  /// thumb_url > cover_url → абсолютний URL
  String? _resolveThumbOrCoverUrl(Map<String, dynamic> book) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? thumb = pick(book['thumb_url'] ?? book['thumbUrl']);
    if (thumb != null) {
      if (thumb.startsWith('http')) return thumb;
      return fullResourceUrl('storage/$thumb');
    }

    String? cover = pick(book['cover_url'] ?? book['coverUrl']);
    if (cover != null) {
      if (cover.startsWith('http')) return cover;
      return fullResourceUrl('storage/$cover');
    }
    return null;
  }

  /// Нормалізуємо карту книги, щоб Book.fromJson отримав абсолютні поля обкладинки
  Map<String, dynamic> _normalizedBookMap(Map<String, dynamic> m) {
    final map = Map<String, dynamic>.from(m);
    final abs = _resolveThumbOrCoverUrl(map);
    if (abs != null) {
      map['thumb_url'] = abs;
      map['thumbUrl'] = abs;
      map['cover_url'] = abs;
      map['coverUrl'] = abs;
    }
    return map;
  }

  void _openBookFromMap(Map<String, dynamic> raw) {
    try {
      final book = Book.fromJson(_normalizedBookMap(raw));
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити книгу')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userNotifier = Provider.of<UserNotifier>(context);
    if (!userNotifier.isAuth) return const LoginScreen();

    debugPrint('Profile: build, isPaidNow=${userNotifier.isPaidNow}');
    return Scaffold(
      appBar: bookaAppBar(actions: const []),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _ProfileLoadingSkeleton();
          }
          if (snapshot.hasError) {
            return _CenteredMessage(
              title: 'Помилка',
              subtitle: safeErrorMessage(
                snapshot.error!,
                fallback: 'Не вдалося завантажити профіль',
              ),
              actionText: 'Спробувати ще',
              onAction: _refresh,
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return _CenteredMessage(
              title: 'Не вдалося завантажити профіль',
              subtitle: 'Перевірте зʼєднання або увійдіть ще раз',
              actionText: 'Оновити',
              onAction: _refresh,
            );
          }

          final favoritesRaw = data['favorites'];
          final listenedRaw = data['listened'];

          final List<Map<String, dynamic>> favorites = (favoritesRaw is List)
              ? favoritesRaw.whereType<Map>().map<Map<String, dynamic>>((m) {
            final out = <String, dynamic>{};
            (m as Map).forEach((k, v) => out['$k'] = v);
            return out;
          }).toList()
              : <Map<String, dynamic>>[];

          final List<Map<String, dynamic>> listened = (listenedRaw is List)
              ? listenedRaw.whereType<Map>().map<Map<String, dynamic>>((m) {
            final out = <String, dynamic>{};
            (m as Map).forEach((k, v) => out['$k'] = v);
            return out;
          }).toList()
              : <Map<String, dynamic>>[];

          final String name = (data['name'] ?? '').toString();
          final String email = (data['email'] ?? '').toString();
          final bool isPaid =
              (data['is_paid'] == true) || (data['isPaid'] == true);

          return RefreshIndicator.adaptive(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _ProfileHeader(
                      name: name.isNotEmpty ? name : 'Користувач',
                      email: email.isNotEmpty ? email : '—',
                      isPaid: isPaid,
                      onLogout: () => logout(context),
                    ),
                  ),
                ),

                // ⬇️ СЕКЦИЯ ПОДПИСКИ (кнопка покупки / статус Premium)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SubscriptionSection(),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: const _SectionTitle('Поточна книга'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: CurrentListenCard(onContinue: _continueListening),
                  ),
                ),

                // Вибране
                SliverToBoxAdapter(
                  child: _PreviewSection(
                    title: 'Вибране',
                    total: favorites.length,
                    emptyText: 'Немає обраних книг',
                    hintText: 'Додайте книги у «вибране» зі сторінки книги',
                    covers: favorites.take(12).map((m) {
                      return _PreviewCover(
                        imageUrl: _resolveThumbOrCoverUrl(m),
                        onTap: () => _openBookFromMap(m),
                      );
                    }).toList(),
                    onSeeAll: favorites.isEmpty
                        ? null
                        : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullBooksGridScreen(
                            title: 'Вибране',
                            items: favorites,
                            resolveUrl: _resolveThumbOrCoverUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Прослухані
                SliverToBoxAdapter(
                  child: _PreviewSection(
                    title: 'Прослухані',
                    total: listened.length,
                    emptyText: 'Немає прослуханих книг',
                    hintText: 'Після завершення книги вона зʼявиться тут',
                    covers: listened.take(12).map((m) {
                      return _PreviewCover(
                        imageUrl: _resolveThumbOrCoverUrl(m),
                        onTap: () => _openBookFromMap(m),
                      );
                    }).toList(),
                    onSeeAll: listened.isEmpty
                        ? null
                        : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullBooksGridScreen(
                            title: 'Прослухані',
                            items: listened,
                            resolveUrl: _resolveThumbOrCoverUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        onTap: _onBottomTab,
        onOpenPlayer: _openPlayer,
        onPlayerTap: _openPlayer,
      ),
    );
  }
}

/// ===== Допоміжні міні-виджети профілю =====

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleSmall;
    return Text(
      text,
      style: t?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final String title;
  final int total;
  final List<_PreviewCover> covers;
  final String emptyText;
  final String? hintText;
  final VoidCallback? onSeeAll;

  const _PreviewSection({
    required this.title,
    required this.total,
    required this.covers,
    required this.emptyText,
    this.hintText,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = total > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (hasItems && onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: Text('Усі ($total)')),
            ],
          ),
          const SizedBox(height: 6),
          if (!hasItems)
            _EmptySection(text: emptyText, hint: hintText)
          else
            SizedBox(
              height: 158,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 4),
                itemBuilder: (context, i) => covers[i],
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: covers.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewCover extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback? onTap;

  const _PreviewCover({
    required this.imageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.black12;
    final iconColor = isDark ? Colors.white54 : Colors.black45;

    Widget frame(Widget child) => SizedBox(
      width: 96,
      height: 128,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(color: bg),
          child: child,
        ),
      ),
    );

    final placeholder = frame(
      Center(child: Icon(Icons.book_rounded, color: iconColor, size: 30)),
    );

    final image = frame(
      Image.network(
        imageUrl ?? '',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(width: 20, height: 20, child: LoadingIndicator(size: 20)),
          );
        },
      ),
    );

    final coverCore = (imageUrl == null || imageUrl!.isEmpty) ? placeholder : image;

    final cover = onTap == null
        ? coverCore
        : Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: coverCore,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        cover,
        const SizedBox(height: 6),
        Opacity(opacity: 0.0, child: Text('•', style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionText;
  final Future<void> Function()? onAction;

  const _CenteredMessage({
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  ),
                ),
              ],
              if (onAction != null && actionText != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onAction, child: Text(actionText!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ===== ИСПРАВЛЕНО: бейдж вынесен ПОД Row и тянется на всю ширину карточки
class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final bool isPaid;
  final VoidCallback onLogout;

  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.isPaid,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initialsOf(name);
    final statusColor = isPaid ? Colors.green : Colors.orange;
    final statusText = isPaid ? 'Платний' : 'Безкоштовний';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(
              theme.brightness == Brightness.dark ? 0.10 : 0.06,
            ),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withOpacity(
            theme.brightness == Brightness.dark ? 0.15 : 0.08,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                child: Text(
                  initials,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withOpacity(0.45)),
                      ),
                      child: Text(
                        statusText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onLogout,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Вийти'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const MinutesBadge(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class _EmptySection extends StatelessWidget {
  final String text;
  final String? hint;
  const _EmptySection({required this.text, this.hint});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(
          Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.35,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: t.bodySmall?.copyWith(
                color: t.bodySmall?.color?.withOpacity(0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileLoadingSkeleton extends StatelessWidget {
  const _ProfileLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.24 : 0.35,
    );

    Widget bar({double h = 12, double w = double.infinity, double r = 8}) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(r),
      ),
    );

    return SafeArea(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(radius: 28, backgroundColor: base),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(h: 16, w: 140, r: 6),
                        const SizedBox(height: 8),
                        bar(h: 12, w: 200, r: 6),
                        const SizedBox(height: 12),
                        bar(h: 18, w: 92, r: 9),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: bar(h: 16, w: 120),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: bar(h: 112, r: 14),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: bar(h: 16, w: 96),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: bar(h: 110, r: 14),
              ),
              childCount: 3,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

// ================== SUBSCRIPTION SECTION ==================
// Комментарии на русском, сам код/строки — українські.
// Этот виджет показывает кнопку покупки Premium, делает покупку
// через Google Play, шлёт verify на бэк и обновляет профіль.

class SubscriptionSection extends StatefulWidget {
  const SubscriptionSection({super.key});

  @override
  State<SubscriptionSection> createState() => _SubscriptionSectionState();
}

class _SubscriptionSectionState extends State<SubscriptionSection> {
  static const String kProductId = 'booka_premium_month'; // ← ID в Play Console
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _isQuerying = false;
  bool _isBuying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    debugPrint('Billing: SubscriptionSection init, product=$kProductId, platform=${Platform.isAndroid ? "android" : "other"}');
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e, st) {
      debugPrint('Billing: stream error: $e');
      setState(() => _error = 'Помилка оплати. Спробуйте ще раз.');
    });
    _queryProduct();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Запросить товар в Play
  Future<void> _queryProduct() async {
    setState(() {
      _isQuerying = true;
      _error = null;
    });
    try {
      debugPrint('Billing: start query for $kProductId');
      final available = await _iap.isAvailable();
      debugPrint('Billing: isAvailable = $available');

      if (!available) {
        setState(() {
          _error = 'Оплата недоступна на пристрої';
          _isQuerying = false;
        });
        return;
      }
      final resp = await _iap.queryProductDetails({kProductId});
      debugPrint('Billing: notFoundIDs = ${resp.notFoundIDs}');
      debugPrint('Billing: found = ${resp.productDetails.map((p) => "${p.id} | ${p.title} | ${p.price}").toList()}');

      if (resp.notFoundIDs.isNotEmpty || resp.productDetails.isEmpty) {
        setState(() {
          _error = 'Товар не знайдено ($kProductId)';
          _isQuerying = false;
        });
        return;
      }
      setState(() {
        _product = resp.productDetails.first;
        _isQuerying = false;
      });
    } catch (e, st) {
      debugPrint('Billing: _queryProduct error: $e\n$st');
      setState(() {
        _error = 'Не вдалося завантажити товар';
        _isQuerying = false;
      });
    }
  }

  // Обработка результатов покупки
  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      debugPrint('Billing: purchase event -> id=${p.productID} status=${p.status} pending=${p.pendingCompletePurchase}');
      if (p.status == PurchaseStatus.pending) {
        setState(() => _isBuying = true);
      } else if (p.status == PurchaseStatus.error) {
        debugPrint('Billing: purchase error -> ${p.error}');
        setState(() {
          _isBuying = false;
          _error = 'Помилка оплати';
        });
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        // Для Android берём purchaseToken
        final token = p.verificationData.serverVerificationData;
        debugPrint('Billing: purchased/restored, sending verify token=${token.substring(0, token.length.clamp(0, 12))}...');
        try {
          // Отправляем на бэк verify
          await ApiClient.i().post('/subscriptions/play/verify', data: {
            'purchase_token': token,
            'product_id': kProductId,
          });

          // Завершаем покупку в Play (acknowledge), после успешной верификации
          if (p.pendingCompletePurchase) {
            debugPrint('Billing: completing purchase (acknowledge)');
            await _iap.completePurchase(p);
          }

          // Обновляем профиль и статус платности
          if (mounted) {
            debugPrint('Billing: refresh user from /auth/me');
            await context.read<UserNotifier>().refreshUserFromMe();
          }

          setState(() {
            _isBuying = false;
            _error = null;
          });
        } catch (e, st) {
          debugPrint('Billing: verify failed -> $e\n$st');
          // Если бэк не принял — не завершаем purchase
          setState(() {
            _isBuying = false;
            _error = 'Не вдалося підтвердити покупку на сервері';
          });
        }
      }
    }
  }

  Future<void> _buy() async {
    final product = _product;
    if (product == null) {
      debugPrint('Billing: _buy() called but _product is null');
      return;
    }
    setState(() {
      _isBuying = true;
      _error = null;
    });
    final param = PurchaseParam(productDetails: product);
    try {
      debugPrint('Billing: buyNonConsumable for ${product.id}');
      // Для підписок у in_app_purchase використовується buyNonConsumable
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e, st) {
      debugPrint('Billing: buy error -> $e\n$st');
      setState(() {
        _isBuying = false;
        _error = 'Не вдалося ініціювати покупку';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userN = context.watch<UserNotifier>();
    final isPaidNow = userN.isPaidNow;
    debugPrint('Billing: build section, isPaidNow=$isPaidNow, productLoaded=${_product != null}, querying=$_isQuerying, error=$_error');

    // Якщо користувач вже Premium — показуємо статус замість кнопки
    if (isPaidNow) {
      final until = userN.user?.paidUntil;
      final subtitle =
      until != null ? 'Активно до: ${until.toLocal()}' : 'Преміум активний';
      return _CardWrap(
        title: 'Booka Premium',
        child: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    // Гость або free — показуємо кнопку покупки
    Widget body;
    if (_isQuerying) {
      body = const Text('Завантаження…');
    } else if (_error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _queryProduct,
            child: const Text('Спробувати ще раз'),
          ),
        ],
      );
    } else if (_product == null) {
      body = OutlinedButton(
        onPressed: _queryProduct,
        child: const Text('Оновити'),
      );
    } else {
      final price = _product!.price; // локалізована ціна
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Місячна підписка: $price',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _isBuying ? null : _buy,
            child: Text(_isBuying ? 'Обробка…' : 'Підключити Premium'),
          ),
        ],
      );
    }

    return _CardWrap(title: 'Booka Premium', child: body);
  }
}

// Невелика карточка-обгортка для секції
class _CardWrap extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardWrap({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
