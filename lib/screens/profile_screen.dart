// lib/screens/profile_screen.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:characters/characters.dart';
import 'package:flutter/services.dart' show PlatformException; // 👈 добавлено

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
// 🔗 для verify после покупки
import 'package:booka_app/core/network/api_client.dart';
import 'package:booka_app/core/network/app_exception.dart'; // Для проверки статуса ошибки
// Billing (встроенный флоу Google Play)
import 'package:in_app_purchase/in_app_purchase.dart';

// ⬇️ для getUserType / UserType
import 'package:booka_app/models/user.dart' show UserType, getUserType;

/// ===== ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ (подняты НАВЕРХ) =====

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
  const _ProfileLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.24 : 0.35,
    );

    Widget bar({double h = 12, double w = double.infinity, double r = 8}) =>
        Container(
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

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final bool isPaid;
  final VoidCallback onLogout;

  const _ProfileHeader({
    super.key,
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color
                            ?.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border:
                        Border.all(color: statusColor.withOpacity(0.45)),
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Вийти'),
              ),
            ],
          ),
          // бейдж минут показываем только для free
          if (!isPaid) ...[
            const SizedBox(height: 6),
            const MinutesBadge(),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _initialsOf(String name) {
    final parts =
    name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _PreviewCover extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback? onTap;

  const _PreviewCover({
    super.key,
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
            child: SizedBox(
                width: 20, height: 20, child: LoadingIndicator(size: 20)),
          );
        },
      ),
    );

    final coverCore =
    (imageUrl == null || imageUrl!.isEmpty) ? placeholder : image;

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
        Opacity(
          opacity: 0.0,
          child: Text('•', style: theme.textTheme.bodySmall),
        ),
      ],
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
    super.key,
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

class _CenteredMessage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionText;
  final Future<void> Function()? onAction;

  const _CenteredMessage({
    super.key,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
                style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.bodyMedium?.copyWith(
                    color: theme.bodyMedium?.color?.withOpacity(0.8),
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

/// ================== ОСНОВНОЙ ЭКРАН ПРОФИЛЯ ==================

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
      // ‼️ АВТО-ЛОГАУТ ПРИ 401 (Щоб не зависало на екрані помилки)
      if (e is AppNetworkException && e.statusCode == 401) {
        debugPrint('Profile: 401 detected -> Auto Logout');
        if (mounted) {
          // Трохи чекаємо, щоб не було бліку
          Future.microtask(() => logout(context));
        }
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    debugPrint('Profile: pull-to-refresh');
    final audio = context.read<AudioPlayerProvider>();

    final user = context.read<UserNotifier>();
    final futProfile = _fetchUserProfile(force: true);
    final futUser = user.fetchCurrentUser();

    final hasLocal = await audio.hasSavedSession();
    final futHydrate =
    hasLocal ? Future.value(false) : audio.hydrateFromServerIfAvailable();

    setState(() => profileFuture = futProfile);
    await Future.wait([futProfile, futHydrate, futUser]);
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
    final userNotifier = context.watch<UserNotifier>();

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
            // Якщо 401 - вже спрацював автологаут, але покажемо лоадер
            if (snapshot.error is AppNetworkException &&
                (snapshot.error as AppNetworkException).statusCode == 401) {
              return const Center(child: LoadingIndicator());
            }
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
                      isPaid: userNotifier.isPaidNow,
                      onLogout: () => logout(context),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SubscriptionSection(),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: _SectionTitle('Поточна книга'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: CurrentListenCard(onContinue: _continueListening),
                  ),
                ),

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

                SliverToBoxAdapter(
                  child: _PreviewSection(
                    title: 'Прослухані',
                    total: listened.length,
                    emptyText: 'Немає прослуханих книг',
                    hintText:
                    'Після завершення книги вона зʼявиться тут',
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

/// ================== SUBSCRIPTION SECTION ==================

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

  // 👇 новый флаг, чтобы не дёргать реинициализацию параллельно
  bool _isReconnectingBilling = false;
  // 👇 флаг автоповтора после "BillingClient is unset"
  bool _isAutoReloadingBilling = false;
  // 👇 блокировка, чтобы не крутиться в retry-цикле, пока не закінчиться реініт
  bool _stopRetriesUntilReinitCompletes = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
        'Billing: SubscriptionSection init, product=$kProductId, platform=${Platform.isAndroid ? "android" : "other"}');

    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e, st) {
      debugPrint('Billing: stream error: $e');
      if (mounted) {
        setState(() => _error = 'Помилка оплати. Спробуйте ще раз.');
      }
    });

    // ‼️ Викликаємо ініціалізацію з невеликою затримкою, щоб дати Flutter час стабілізуватися
    // Це часто вирішує проблему "not found" при швидкому переході
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Маленька затримка для Android (InAppPurchasePlugin іноді потребує часу)
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // ‼️ Викликаємо обгортку з повторними спробами
    await _queryProductWithRetry();

    try {
      debugPrint('Billing: restorePurchases()');
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('Billing: restorePurchases error: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 🔄 Реинициализация BillingClient при "BillingClient is unset"
  Future<void> _tryReinitBillingClient() async {
    if (_isReconnectingBilling) {
      debugPrint('Billing: [reinit] already in progress, skip');
      return;
    }

    _isReconnectingBilling = true;
    debugPrint('Billing: [reinit] start re-init flow (like on app start)');

    try {
      if (Platform.isAndroid) {
        debugPrint(
            'Billing: [reinit] Android, small delay before restorePurchases');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('Billing: [reinit] calling restorePurchases()...');
      await _iap.restorePurchases();
      debugPrint('Billing: [reinit] restorePurchases() finished');
    } catch (e, st) {
      debugPrint('Billing: [reinit] restorePurchases error: $e\n$st');
    } finally {
      _isReconnectingBilling = false;
      debugPrint('Billing: [reinit] done');
    }
  }

  // ‼️ ОБГОРТКА: кілька спроб підключення/запиту ‼️
  Future<void> _queryProductWithRetry() async {
    if (_stopRetriesUntilReinitCompletes) {
      // вже очікуємо автоперезапуск після reinit — нові спроби не робимо
      return;
    }

    const maxRetries = 5; // Збільшено до 5, щоб впоратися з таймаутами
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _queryProduct();
        if (_product != null) return; // Успіх

        if (_stopRetriesUntilReinitCompletes) {
          // Після "BillingClient is unset" виходимо з циклу, щоб дочекатися реініту
          return;
        }

        // Якщо повернувся null без помилки, значить, можливо, ще не підключилися
        if (attempt < maxRetries) {
          debugPrint(
              'Billing: Product not found (Attempt $attempt). Retrying in 1s...');
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        final errorString = e.toString();

        // Перевіряємо на типові помилки відключення
        final isBillingClientUnset = errorString.contains('BillingClient is unset') ||
            errorString.contains('Service is disconnected') ||
            errorString.contains('not available for purchase');

        if (isBillingClientUnset && attempt < maxRetries) {
          debugPrint(
              'Billing: Connection error detected (Attempt $attempt). Retrying in 2s...');
          // Збільшуємо затримку, щоб дати Play Service час на відновлення
          await Future.delayed(const Duration(seconds: 2));
          continue; // Повторити спробу
        }

        // Якщо це не помилка з'єднання або остання спроба, встановлюємо помилку
        if (mounted) {
          setState(() {
            _error =
            'Не вдалося завантажити товар: $errorString (Спроба $attempt/$maxRetries)';
            _isQuerying = false;
          });
        }
        return; // Вихід з циклу
      }
    }
  }

  // ‼️ ЗМІНЕНИЙ МЕТОД: один запит + спец. обробка PlatformException(BillingClient is unset) ‼️
  Future<void> _queryProduct() async {
    if (!mounted) return;
    setState(() {
      _isQuerying = true;
      _error = null;
    });

    debugPrint('Billing: Starting single query for $kProductId...');

    try {
      final available = await _iap.isAvailable();
      debugPrint('Billing: isAvailable() = $available');
      if (!available) {
        throw Exception(
            'Оплата недоступна на пристрої (Store unavailable / isAvailable=false)');
      }

      final resp = await _iap.queryProductDetails({kProductId});
      debugPrint(
          'Billing: queryProductDetails -> notFoundIDs=${resp.notFoundIDs}, products=${resp.productDetails.length}');

      if (resp.productDetails.isEmpty) {
        // Викидаємо помилку, щоб її спіймав _queryProductWithRetry
        throw Exception(
            'Товар не знайдено ($kProductId). Перевірте інтернет або ID товару.');
      }

      if (mounted) {
        final pd = resp.productDetails.first;
        setState(() {
          _product = pd;
          _isQuerying = false;
        });
      }
    } on PlatformException catch (e, st) {
      debugPrint(
          'Billing: _queryProduct PlatformException code=${e.code}, message=${e.message}\n$st');

      // 👇 наш кейс: BillingClient is unset → запускаем реинициализацию, НО не кидаем дальше
      if (e.code == 'UNAVAILABLE' &&
          (e.message ?? '').contains('BillingClient is unset')) {
        debugPrint(
            'Billing: BillingClient is unset → run _tryReinitBillingClient()');
        _stopRetriesUntilReinitCompletes = true;
        await _tryReinitBillingClient();

        if (!mounted) return;
        setState(() {
          _error =
          'Google Play Billing перезапускається. Спробуйте ще раз за кілька секунд.';
          _isQuerying = false;
        });

        // 👇 автоматичний повтор запиту товару (імітація «перезапуску» застосунку)
        await _autoReloadProductAfterReinit();
        // Не кидаем исключение дальше, чтобы _queryProductWithRetry не перезаписывал наше сообщение
        return;
      }

      // все остальные PlatformException отдаем наверх в _queryProductWithRetry
      rethrow;
    }
  }

  /// ⚙️ Автоперезапуск запиту продукту після реініціалізації billing
  Future<void> _autoReloadProductAfterReinit() async {
    if (_isAutoReloadingBilling) {
      debugPrint('Billing: [auto-reload] already scheduled, skip');
      return;
    }
    _isAutoReloadingBilling = true;

    try {
      debugPrint('Billing: [auto-reload] wait 2s and query product again');
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      debugPrint('Billing: [auto-reload] re-run _queryProductWithRetry()');
      _stopRetriesUntilReinitCompletes = false; // після паузи — можна знову пробувати
      await _queryProductWithRetry();
    } finally {
      _isAutoReloadingBilling = false;
      debugPrint('Billing: [auto-reload] done');
    }
  }

  /// ⚠️ "опитування" статусу ПІСЛЯ покупки
  Future<void> _pollPaidStatus() async {
    final userN = context.read<UserNotifier>();
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 2));
      await userN.refreshUserFromMe();
      debugPrint('Billing: poll paid? -> ${userN.isPaidNow}');
      if (!mounted) return;
      if (userN.isPaidNow) {
        // як тільки сервер сказав, що юзер платний —
        // синхронізуємо тип користувача в AudioPlayerProvider,
        // щоб GlobalBannerInjector одразу прибрав рекламу
        final u = userN.user;
        if (u != null) {
          final audio = context.read<AudioPlayerProvider>();
          audio.userType = getUserType(u);
          // 👇 важливо: повідомляємо слухачів (в т.ч. GlobalBannerInjector)
          audio.notifyListeners();
        }

        setState(() {});
        return;
      }
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      debugPrint(
          'Billing: purchase event -> id=${p.productID} status=${p.status} pending=${p.pendingCompletePurchase}');

      if (!mounted) return;

      if (p.status == PurchaseStatus.pending) {
        setState(() => _isBuying = true);
      } else if (p.status == PurchaseStatus.error) {
        debugPrint('Billing: purchase error -> ${p.error}');
        setState(() {
          _isBuying = false;
          _error = 'Помилка: ${p.error?.message ?? "Unknown error"}';
        });
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final token = p.verificationData.serverVerificationData;
        final short =
        token.isNotEmpty ? token.substring(0, token.length.clamp(0, 12)) : '';
        debugPrint(
            'Billing: purchased/restored, sending verify token=$short...');

        try {
          await ApiClient.i().post('/subscriptions/play/verify', data: {
            'purchaseToken': token,
            'productId': kProductId,
          });

          if (mounted) {
            debugPrint('Billing: refresh user from /auth/me (immediate)');
            final userN = context.read<UserNotifier>();
            await userN.refreshUserFromMe();

            // одразу після оновлення профілю синхронізуємо userType в плеєрі
            final u = userN.user;
            if (u != null) {
              final audio = context.read<AudioPlayerProvider>();
              audio.userType = getUserType(u);
              // 👇 тут теж оповіщаємо, щоб банер зник одразу
              audio.notifyListeners();
            }

            // на випадок, якщо /auth/me затримався
            unawaited(_pollPaidStatus());
          }

          if (p.pendingCompletePurchase) {
            debugPrint('Billing: completing purchase (acknowledge)');
            await _iap.completePurchase(p);
          }

          if (mounted) {
            setState(() {
              _isBuying = false;
              _error = null;
            });
          }
        } catch (e, st) {
          debugPrint('Billing: verify failed -> $e\n$st');
          if (mounted) {
            setState(() {
              _isBuying = false;
              _error =
              'Не вдалося підтвердити покупку на сервері. Спробуйте оновити екран.';
            });
          }
        }
      } else if (p.status == PurchaseStatus.canceled) {
        debugPrint('Billing: purchase canceled');
        if (mounted) {
          setState(() {
            _isBuying = false;
            _error = null;
          });
        }
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }
    }
  }

  // ✅ Покупка без offerToken/GooglePlayPurchaseParam
  Future<void> _buy() async {
    final product = _product;
    if (product == null) {
      debugPrint(
          'Billing: _buy() called but _product is null. Retry querying.');
      await _queryProductWithRetry(); // 👈 ВИКЛИКАЄМО НОВИЙ МЕТОД
      if (_product == null) return; // Все ще нуль
    }

    setState(() {
      _isBuying = true;
      _error = null;
    });

    try {
      debugPrint('Billing: buy for ${_product!.id}');
      final param = PurchaseParam(productDetails: _product!);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e, st) {
      debugPrint('Billing: buy error -> $e\n$st');
      if (mounted) {
        setState(() {
          _isBuying = false;
          _error = 'Не вдалося ініціювати покупку: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userN = context.watch<UserNotifier>();
    final isPaidNow = userN.isPaidNow;
    debugPrint(
        'Billing: build section, isPaidNow=$isPaidNow, productLoaded=${_product != null}, querying=$_isQuerying, error=$_error');

    if (isPaidNow) {
      final until = userN.user?.paidUntil;
      final subtitle = until != null
          ? 'Активно до: ${until.toLocal().toString().substring(0, 10)}'
          : 'Преміум активний';
      return _CardWrap(
        title: 'Booka Premium',
        child: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    Widget body;
    if (_isQuerying) {
      body = const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Завантаження підписки…'),
        ],
      );
    } else if (_error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: TextStyle(
                color: Theme.of(context).colorScheme.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _queryProductWithRetry,
                child: const Text('Оновити'),
              ),
              OutlinedButton(
                onPressed: () async {
                  try {
                    await _iap.restorePurchases();
                  } catch (_) {}
                },
                child: const Text('Відновити'),
              ),
            ],
          ),
        ],
      );
    } else if (_product == null) {
      body = Row(
        children: [
          const Expanded(child: Text('Немає інформації про товар')),
          OutlinedButton(
            onPressed: _queryProductWithRetry,
            child: const Text('Оновити'),
          ),
        ],
      );
    } else {
      final price = _product!.price;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Місячна підписка: $price',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: _isBuying ? null : _buy,
                child: Text(_isBuying ? 'Обробка…' : 'Підключити Premium'),
              ),
              OutlinedButton(
                onPressed: () async {
                  try {
                    await _iap.restorePurchases();
                  } catch (_) {}
                },
                child: const Text('Відновити покупку'),
              ),
            ],
          ),
        ],
      );
    }

    return _CardWrap(title: 'Booka Premium', child: body);
  }
}

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
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
