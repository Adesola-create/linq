import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'chat_page.dart';
import 'linq_theme.dart';

/// Extracts a one-line preview of a thread's last message, handling APIs that
/// return it as a plain string field or as a nested message object (e.g.
/// `{"last_message": {"body": "...", "kind": "voice"}}`).
String _lastMessagePreview(Map<String, dynamic> thread) {
  dynamic msg = thread['last_message'] ??
      thread['last_message_body'] ??
      thread['latest_message'] ??
      thread['recent_message'] ??
      thread['preview'];

  if (msg is Map) {
    final kind = (msg['kind'] ?? msg['type'] ?? '').toString().toLowerCase();
    if (kind == 'voice' || kind == 'audio') return '🎤 Voice message';
    for (final key in ['body', 'text', 'content', 'message']) {
      final v = msg[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  return msg?.toString().trim() ?? '';
}

class CustomerMessagesPage extends StatefulWidget {
  const CustomerMessagesPage({super.key});

  @override
  State<CustomerMessagesPage> createState() => _CustomerMessagesPageState();
}

class _CustomerMessagesPageState extends State<CustomerMessagesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'Messages',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: LinqColors.textOnBrand,
          indicatorWeight: 3,
          labelColor: LinqColors.textOnBrand,
          unselectedLabelColor: LinqColors.textOnBrand.withValues(alpha: 0.6),
          labelStyle: LinqTextStyles.labelSm
              .copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: LinqTextStyles.labelSm,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Unread'),
            Tab(text: 'Jobs'),
            Tab(text: 'Direct'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ThreadList(filter: 'all'),
          _ThreadList(filter: 'unread'),
          _ThreadList(filter: 'job'),
          _ThreadList(filter: 'direct'),
        ],
      ),
    );
  }
}

class _ThreadList extends StatefulWidget {
  final String filter;
  const _ThreadList({required this.filter});

  @override
  State<_ThreadList> createState() => _ThreadListState();
}

class _ThreadListState extends State<_ThreadList>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenRefresh();
  }

  bool get _isUnreadTab => widget.filter == 'unread';
  bool get _isJobTab => widget.filter == 'job';

  static int _threadUnread(Map<String, dynamic> t) {
    final v = t['unread_count'] ?? t['unread_messages_count'] ?? 0;
    return v is int ? v : int.tryParse(v.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _applyLocalFilters(
      List<Map<String, dynamic>> threads) {
    if (_isUnreadTab) {
      return threads.where((t) => _threadUnread(t) > 0).toList();
    }
    if (_isJobTab) {
      return threads.where((t) {
        final kind = (t['kind'] ?? t['type'] ?? '').toString().toLowerCase();
        return kind == 'job' || t['job_ulid'] != null || t['job'] != null;
      }).toList();
    }
    return threads;
  }

  /// Shows whatever was cached for this account/tab immediately (so the
  /// screen never starts blank), then silently refreshes from the network.
  Future<void> _loadFromCacheThenRefresh() async {
    final cached = await AuthService.getCachedThreads(
      widget.filter == 'all' ? null : widget.filter,
    );
    if (!mounted) return;
    if (cached != null) {
      final threads = _applyLocalFilters(
        cached.whereType<Map<String, dynamic>>().toList(),
      );
      setState(() {
        _threads = threads;
        _loading = false;
      });
      _loadLastMessagePreviews();
    }
    await _load(silent: cached != null);
  }

  /// The /threads list endpoint only returns `last_message_at`, not the
  /// message text itself, so fetch each thread's most recent message
  /// separately (existing /messages?thread_ulid=&limit=1 endpoint) and
  /// attach it to the thread map for the tile preview to pick up.
  Future<void> _loadLastMessagePreviews() async {
    await Future.wait(_threads.map(_fetchLastMessageFor));
  }

  Future<void> _fetchLastMessageFor(Map<String, dynamic> thread) async {
    final ulid =
        (thread['ulid'] ?? thread['thread_ulid'] ?? thread['id'])
            ?.toString() ??
            '';
    if (ulid.isEmpty) return;
    final result = await AuthService.getMessages(threadUlid: ulid, limit: 1);
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>? ?? [];
      if (raw.isNotEmpty && raw.last is Map) {
        setState(() {
          thread['last_message'] =
              Map<String, dynamic>.from(raw.last as Map);
        });
      }
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted && !silent) setState(() { _loading = true; _error = null; });
    final result = await AuthService.getThreads(
      filter: widget.filter == 'all' ? null : widget.filter,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>? ?? [];
      final threads = _applyLocalFilters(
        raw.whereType<Map<String, dynamic>>().toList(),
      );
      setState(() {
        _threads = threads;
        _loading = false;
        _error = null;
      });
      _loadLastMessagePreviews();
      // Keep global badge in sync (only "all" tab has the full picture)
      if (!_isUnreadTab && widget.filter == 'all') {
        int total = 0;
        for (final t in _threads) {
          total += _threadUnread(t);
        }
        AuthService.unreadMessageCount.value = total;
      }
    } else if (result['auth_required'] == true) {
      if (!silent) setState(() { _loading = false; });
      if (AuthService.claimLoginRedirect()) {
        await AuthService.logout();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        }
      }
    } else {
      // On a silent background refresh, keep showing whatever we already
      // have rather than replacing the list with an error state.
      if (!silent) {
        setState(() {
          _loading = false;
          _error = result['message']?.toString() ?? 'Failed to load messages.';
        });
      }
    }
  }

  Future<void> _markThreadRead(String threadUlid, int index) async {
    await AuthService.markThreadRead(threadUlid);
    if (!mounted) return;
    setState(() => _threads.removeAt(index));
    // Decrement global badge
    if (AuthService.unreadMessageCount.value > 0) {
      AuthService.unreadMessageCount.value--;
    }
  }

  Future<void> _markAllAsRead() async {
    final toMark = List<Map<String, dynamic>>.from(_threads);
    setState(() => _threads.clear());
    AuthService.unreadMessageCount.value = 0;
    for (final t in toMark) {
      final ulid = (t['ulid'] ?? '').toString();
      if (ulid.isNotEmpty) await AuthService.markThreadRead(ulid);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: LinqColors.forest500),
      );
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load messages',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_threads.isEmpty) {
      return _EmptyState(
        icon: _isJobTab
            ? Icons.work_outline_rounded
            : Icons.chat_bubble_outline_rounded,
        title: _isUnreadTab
            ? 'No unread messages'
            : _isJobTab
                ? 'No job conversations yet'
                : 'No messages yet',
        message: _isUnreadTab
            ? 'You\'re all caught up!'
            : _isJobTab
                ? 'When a provider applies for your job, you can message them here to get started.'
                : 'Your conversations with providers will appear here.',
        actionLabel: 'Refresh',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      color: LinqColors.forest500,
      onRefresh: () => _load(silent: true),
      child: Column(
        children: [
          if (_isUnreadTab)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s5,
                vertical: LinqSpacing.s2,
              ),
              color: LinqColors.bgSurface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_threads.length} unread',
                    style: LinqTextStyles.bodySm.copyWith(
                      color: LinqColors.textSecondary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _markAllAsRead,
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Mark all as read'),
                    style: TextButton.styleFrom(
                      foregroundColor: LinqColors.forest500,
                      padding: const EdgeInsets.symmetric(
                        horizontal: LinqSpacing.s3,
                        vertical: LinqSpacing.s1,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: LinqTextStyles.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _threads.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: LinqColors.borderDefault),
              itemBuilder: (context, i) {
                final thread = _threads[i];
                if (_isJobTab) {
                  return _JobThreadTile(
                    thread: thread,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(thread: thread),
                        ),
                      );
                      _load(silent: true);
                    },
                  );
                }
                return _ThreadTile(
                  thread: thread,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(thread: thread),
                      ),
                    );
                    _load(silent: true);
                  },
                  onMarkRead: _isUnreadTab
                      ? () => _markThreadRead(
                            (thread['ulid'] ?? '').toString(),
                            i,
                          )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final Map<String, dynamic> thread;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;
  const _ThreadTile({required this.thread, required this.onTap, this.onMarkRead});

  static const _photoKeys = [
    'photo_url', 'profile_photo', 'profile_photo_url',
    'avatar_url', 'image_url', 'image', 'avatar', 'picture',
  ];
  static const _nameKeys = ['name', 'full_name', 'business_name', 'display_name'];

  Map<String, dynamic>? get _otherParticipant {
    // 1. Check participants array (handle any role casing)
    final participants = thread['participants'];
    if (participants is List) {
      for (final p in participants) {
        if (p is Map) {
          final role = (p['role'] ?? '').toString().toLowerCase();
          if (role == 'prov' || role == 'provider') {
            return p.cast<String, dynamic>();
          }
        }
      }
    }
    // 2. Top-level provider/other_user object some APIs return directly
    for (final key in ['provider', 'other_user', 'other_party', 'recipient']) {
      final v = thread[key];
      if (v is Map) return v.cast<String, dynamic>();
    }
    return null;
  }

  String get _name {
    final p = _otherParticipant;
    if (p != null) {
      for (final key in _nameKeys) {
        final v = p[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    // Fallback: thread-level name fields
    for (final key in ['provider_name', 'name', 'title']) {
      final v = thread[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return 'Provider';
  }

  String get _avatar {
    final p = _otherParticipant;
    if (p != null) {
      for (final key in _photoKeys) {
        final v = p[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  String get _lastMessage => _lastMessagePreview(thread);

  String get _timeLabel {
    final raw = (thread['last_message_at'] ??
            thread['updated_at'] ??
            thread['created_at'])
        ?.toString();
    if (raw == null) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${local.day}/${local.month}';
  }

  int get _unreadCount {
    final v = thread['unread_count'] ??
        thread['unread_messages_count'] ??
        0;
    return v is int ? v : int.tryParse(v.toString()) ?? 0;
  }

  bool get _isJobThread {
    final kind = (thread['kind'] ?? thread['type'] ?? '').toString().toLowerCase();
    return kind == 'job' || thread['job_ulid'] != null;
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    final avatarUrl = _avatar;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread > 0 ? LinqColors.forest50 : null,
        padding: const EdgeInsets.symmetric(
          horizontal: LinqSpacing.s5,
          vertical: LinqSpacing.s4,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: LinqColors.forest100,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: LinqColors.forest500,
                          size: 26,
                        )
                      : null,
                ),
                if (_isJobThread)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: LinqColors.forest500,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.work_rounded,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: LinqSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _name,
                          style: LinqTextStyles.body.copyWith(
                            color: LinqColors.textPrimary,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_timeLabel.isNotEmpty) ...[
                        const SizedBox(width: LinqSpacing.s2),
                        Text(
                          _timeLabel,
                          style: LinqTextStyles.bodyXs.copyWith(
                            color: unread > 0
                                ? LinqColors.forest500
                                : LinqColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_lastMessage.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _lastMessage,
                      style: LinqTextStyles.bodySm.copyWith(
                        color: unread > 0
                            ? LinqColors.textPrimary
                            : LinqColors.textSecondary,
                        fontWeight: unread > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (onMarkRead != null) ...[
              const SizedBox(width: LinqSpacing.s1),
              IconButton(
                tooltip: 'Mark as read',
                onPressed: onMarkRead,
                icon: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: LinqColors.forest500,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ] else if (unread > 0) ...[
              const SizedBox(width: LinqSpacing.s2),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: const BoxDecoration(
                  color: LinqColors.forest500,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    unread > 99 ? '99+' : unread.toString(),
                    style: LinqTextStyles.bodyXs.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JobThreadTile extends StatelessWidget {
  final Map<String, dynamic> thread;
  final VoidCallback onTap;
  const _JobThreadTile({required this.thread, required this.onTap});

  static const _photoKeys = [
    'photo_url', 'profile_photo', 'profile_photo_url',
    'avatar_url', 'image_url', 'image', 'avatar', 'picture',
  ];
  static const _nameKeys = ['name', 'full_name', 'business_name', 'display_name'];

  Map<String, dynamic>? get _provider {
    final participants = thread['participants'];
    if (participants is List) {
      for (final p in participants) {
        if (p is Map) {
          final role = (p['role'] ?? '').toString().toLowerCase();
          if (role == 'prov' || role == 'provider') {
            return p.cast<String, dynamic>();
          }
        }
      }
    }
    for (final key in ['provider', 'other_user', 'other_party']) {
      final v = thread[key];
      if (v is Map) return v.cast<String, dynamic>();
    }
    return null;
  }

  String get _providerName {
    final p = _provider;
    if (p != null) {
      for (final key in _nameKeys) {
        final v = p[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    for (final key in ['provider_name']) {
      final v = thread[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return 'Provider';
  }

  String get _providerAvatar {
    final p = _provider;
    if (p != null) {
      for (final key in _photoKeys) {
        final v = p[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  String get _jobTitle {
    final job = thread['job'];
    if (job is Map) {
      final v = (job['title'] ?? job['name'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    for (final key in ['job_title', 'job_name', 'title']) {
      final v = thread[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return 'Job';
  }

  String get _jobStatus {
    final job = thread['job'];
    if (job is Map) {
      return (job['status'] ?? '').toString().trim();
    }
    return (thread['job_status'] ?? '').toString().trim();
  }

  String get _lastMessage => _lastMessagePreview(thread);

  String get _timeLabel {
    final raw = (thread['last_message_at'] ??
            thread['updated_at'] ??
            thread['created_at'])
        ?.toString();
    if (raw == null) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${local.day}/${local.month}';
  }

  int get _unreadCount {
    final v = thread['unread_count'] ?? thread['unread_messages_count'] ?? 0;
    return v is int ? v : int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    final avatarUrl = _providerAvatar;
    final status = _jobStatus;
    final lastMsg = _lastMessage;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread > 0 ? LinqColors.forest50 : null,
        padding: const EdgeInsets.symmetric(
          horizontal: LinqSpacing.s5,
          vertical: LinqSpacing.s4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: LinqColors.forest100,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: LinqColors.forest500,
                          size: 26,
                        )
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: LinqColors.forest500,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.work_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: LinqSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _providerName,
                          style: LinqTextStyles.body.copyWith(
                            color: LinqColors.textPrimary,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_timeLabel.isNotEmpty) ...[
                        const SizedBox(width: LinqSpacing.s2),
                        Text(
                          _timeLabel,
                          style: LinqTextStyles.bodyXs.copyWith(
                            color: unread > 0
                                ? LinqColors.forest500
                                : LinqColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.work_outline_rounded,
                        size: 13,
                        color: LinqColors.forest500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _jobTitle,
                          style: LinqTextStyles.bodySm.copyWith(
                            color: LinqColors.forest500,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (status.isNotEmpty) ...[
                        const SizedBox(width: LinqSpacing.s2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: LinqColors.forest100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status,
                            style: LinqTextStyles.bodyXs.copyWith(
                              color: LinqColors.forest500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMsg.isNotEmpty
                              ? lastMsg
                              : 'Tap to start the conversation',
                          style: LinqTextStyles.bodySm.copyWith(
                            color: lastMsg.isNotEmpty
                                ? (unread > 0
                                    ? LinqColors.textPrimary
                                    : LinqColors.textSecondary)
                                : LinqColors.forest500,
                            fontWeight: unread > 0 && lastMsg.isNotEmpty
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontStyle: lastMsg.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: LinqSpacing.s2),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: const BoxDecoration(
                            color: LinqColors.forest500,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              unread > 99 ? '99+' : unread.toString(),
                              style: LinqTextStyles.bodyXs.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LinqSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: LinqColors.stone300),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              title,
              style: LinqTextStyles.h4.copyWith(color: LinqColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LinqSpacing.s2),
            Text(
              message,
              style: LinqTextStyles.bodySm
                  .copyWith(color: LinqColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LinqSpacing.s5),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
