import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'linq_theme.dart';

class CustomerNotificationsPage extends StatefulWidget {
  const CustomerNotificationsPage({super.key});

  @override
  State<CustomerNotificationsPage> createState() =>
      _CustomerNotificationsPageState();
}

class _CustomerNotificationsPageState extends State<CustomerNotificationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          'Notifications',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: LinqColors.textOnBrand,
          indicatorWeight: 3,
          labelColor: LinqColors.textOnBrand,
          unselectedLabelColor: LinqColors.textOnBrand.withValues(alpha: 0.6),
          labelStyle:
              LinqTextStyles.labelSm.copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: LinqTextStyles.labelSm,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Unread'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _NotificationList(unreadOnly: false),
          _NotificationList(unreadOnly: true),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationList extends StatefulWidget {
  final bool unreadOnly;
  const _NotificationList({required this.unreadOnly});

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static bool _isUnread(Map<String, dynamic> n) {
    // API returns: read: false (bool)
    final isRead = n['is_read'] ?? n['read'];
    if (isRead is bool) return !isRead;
    if (isRead is num) return isRead == 0;
    final readAt = n['read_at'] ?? n['readAt'];
    if (readAt != null && readAt.toString().trim().isNotEmpty) return false;
    return true;
  }

  static List<Map<String, dynamic>> _extract(dynamic data) {
    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      if (data['data'] is List) {
        raw = data['data'] as List<dynamic>;
      } else if (data['notifications'] is List) {
        raw = data['notifications'] as List<dynamic>;
      } else if (data['items'] is List) {
        raw = data['items'] as List<dynamic>;
      } else if (data['results'] is List) {
        raw = data['results'] as List<dynamic>;
      } else if (data['data'] is Map &&
          (data['data'] as Map)['notifications'] is List) {
        raw = (data['data'] as Map)['notifications'] as List<dynamic>;
      } else {
        raw = [];
      }
    } else {
      raw = [];
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    final result = await AuthService.getNotifications(limit: 50, offset: 0);
    if (!mounted) return;
    if (result['success'] == true) {
      var items = _extract(result['data']);
      if (widget.unreadOnly) {
        items = items.where(_isUnread).toList();
      }
      setState(() { _items = items; _loading = false; });
      // Keep global badge in sync when loading the all tab
      if (!widget.unreadOnly) {
        AuthService.unreadNotificationCount.value =
            items.where(_isUnread).length;
      }
    } else if (result['auth_required'] == true) {
      setState(() { _loading = false; });
      if (AuthService.claimLoginRedirect()) {
        await AuthService.logout();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        }
      }
    } else {
      setState(() {
        _loading = false;
        _error = result['message']?.toString() ?? 'Failed to load notifications.';
      });
    }
  }

  Future<void> _markRead(String ulid, int index) async {
    await AuthService.markNotificationRead(ulid);
    if (!mounted) return;
    if (widget.unreadOnly) {
      setState(() => _items.removeAt(index));
    } else {
      setState(() {
        _items[index] = Map<String, dynamic>.from(_items[index])
          ..['is_read'] = true
          ..['read_at'] = DateTime.now().toIso8601String();
      });
    }
    if (AuthService.unreadNotificationCount.value > 0) {
      AuthService.unreadNotificationCount.value--;
    }
  }

  void _openDetail(Map<String, dynamic> n, String ulid, int index) {
    if (_isUnread(n) && ulid.isNotEmpty) {
      _markRead(ulid, index);
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: LinqColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationDetailSheet(notification: n),
    );
  }

  Future<void> _markAllRead() async {
    if (widget.unreadOnly) {
      setState(() => _items.clear());
    } else {
      final now = DateTime.now().toIso8601String();
      setState(() {
        _items = _items.map((n) {
          return Map<String, dynamic>.from(n)
            ..['is_read'] = true
            ..['read_at'] = now;
        }).toList();
      });
    }
    AuthService.unreadNotificationCount.value = 0;
    await AuthService.markAllNotificationsRead();
    if (!mounted) return;
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
        icon: Icons.notifications_off_outlined,
        title: 'Unable to load notifications',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    if (_items.isEmpty) {
      return _EmptyState(
        icon: Icons.notifications_none_rounded,
        title: widget.unreadOnly ? 'No unread notifications' : 'No notifications yet',
        message: widget.unreadOnly
            ? 'You\'re all caught up!'
            : 'Provider applications, job updates, and messages will appear here.',
        actionLabel: 'Refresh',
        onAction: _load,
      );
    }

    final unreadCount = _items.where(_isUnread).length;

    return RefreshIndicator(
      color: LinqColors.forest500,
      onRefresh: _load,
      child: Column(
        children: [
          if (widget.unreadOnly || unreadCount > 0)
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
                    widget.unreadOnly
                        ? '${_items.length} unread'
                        : '$unreadCount unread',
                    style: LinqTextStyles.bodySm
                        .copyWith(color: LinqColors.textSecondary),
                  ),
                  TextButton.icon(
                    onPressed: unreadCount > 0 ? _markAllRead : null,
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Mark all as read'),
                    style: TextButton.styleFrom(
                      foregroundColor: LinqColors.forest500,
                      disabledForegroundColor:
                          LinqColors.textTertiary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: LinqSpacing.s3,
                        vertical: LinqSpacing.s1,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: LinqTextStyles.bodySm
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(LinqSpacing.s5),
              itemCount: _items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: LinqSpacing.s3),
              itemBuilder: (context, i) {
                final n = _items[i];
                final ulid = (n['ulid'] ?? n['id'] ?? '').toString();
                return _NotificationTile(
                  notification: n,
                  onMarkRead: _isUnread(n) && ulid.isNotEmpty
                      ? () => _markRead(ulid, i)
                      : null,
                  onTap: () => _openDetail(n, ulid, i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared field extraction — used by both the list tile and the detail sheet.

String _notifType(Map<String, dynamic> n) =>
    (n['type'] ?? n['category'] ?? n['event'] ?? '').toString().toLowerCase();

String _notifTitle(Map<String, dynamic> n) {
  for (final key in ['title', 'subject', 'heading']) {
    final v = n[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  final type = _notifType(n);
  if (type.contains('application')) return 'Provider application';
  if (type.contains('message')) return 'New message';
  if (type.contains('job')) return 'Job update';
  return 'Notification';
}

String _notifMessage(Map<String, dynamic> n) {
  for (final key in ['message', 'body', 'description', 'content', 'text']) {
    final v = n[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  return 'Open this notification for more details.';
}

IconData _notifIcon(Map<String, dynamic> n) {
  final type = _notifType(n);
  if (type.contains('application')) return Icons.assignment_turned_in;
  if (type.contains('message')) return Icons.chat_bubble_outline_rounded;
  if (type.contains('job')) return Icons.work_outline_rounded;
  return Icons.notifications_none_rounded;
}

Color _notifAccent(Map<String, dynamic> n) {
  final type = _notifType(n);
  if (type.contains('application')) return LinqColors.trust;
  if (type.contains('message')) return LinqColors.info500;
  if (type.contains('job')) return LinqColors.success500;
  return LinqColors.forest500;
}

DateTime? _notifLocalTime(Map<String, dynamic> n) {
  final raw =
      (n['created_at'] ?? n['createdAt'] ?? n['time'] ?? n['date'])
          ?.toString();
  final parsed = raw == null ? null : DateTime.tryParse(raw);
  return parsed?.toLocal();
}

String _notifRelativeTimeLabel(Map<String, dynamic> n) {
  final local = _notifLocalTime(n);
  if (local == null) return '';
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${local.day}/${local.month}/${local.year}';
}

String _notifFullTimeLabel(Map<String, dynamic> n) {
  final local = _notifLocalTime(n);
  if (local == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day}, ${local.year} • $hour12:$minute $ampm';
}

bool _notifIsUnread(Map<String, dynamic> n) {
  final readAt = n['read_at'] ?? n['readAt'];
  final isRead = n['is_read'] ?? n['read'];
  if (readAt != null && readAt.toString().trim().isNotEmpty) return false;
  if (isRead is bool) return !isRead;
  if (isRead is num) return isRead == 0;
  return true;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    this.onMarkRead,
    this.onTap,
  });

  final Map<String, dynamic> notification;
  final VoidCallback? onMarkRead;
  final VoidCallback? onTap;

  String get _title => _notifTitle(notification);
  String get _message => _notifMessage(notification);
  String get _timeLabel => _notifRelativeTimeLabel(notification);
  bool get _isUnread => _notifIsUnread(notification);
  IconData get _icon => _notifIcon(notification);
  Color get _accent => _notifAccent(notification);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: LinqRadius.borderMd,
      child: InkWell(
        borderRadius: LinqRadius.borderMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(LinqSpacing.s4),
          decoration: BoxDecoration(
            color: LinqColors.bgSurface,
            borderRadius: LinqRadius.borderMd,
            border: Border.all(
              color:
                  _isUnread ? LinqColors.forest200 : LinqColors.borderDefault,
            ),
            boxShadow: LinqShadows.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: LinqRadius.borderMd,
                ),
                child: Icon(_icon, color: _accent, size: 22),
              ),
              const SizedBox(width: LinqSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _title,
                            style: LinqTextStyles.body.copyWith(
                              color: LinqColors.textPrimary,
                              fontWeight: _isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_timeLabel.isNotEmpty) ...[
                          const SizedBox(width: LinqSpacing.s2),
                          Text(
                            _timeLabel,
                            style: LinqTextStyles.bodyXs
                                .copyWith(color: LinqColors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: LinqSpacing.s1),
                    Text(
                      _message,
                      style: LinqTextStyles.bodySm
                          .copyWith(color: LinqColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LinqSpacing.s2),
              if (onMarkRead != null)
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
                )
              else if (_isUnread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: LinqColors.forest500,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationDetailSheet extends StatelessWidget {
  const _NotificationDetailSheet({required this.notification});

  final Map<String, dynamic> notification;

  @override
  Widget build(BuildContext context) {
    final icon = _notifIcon(notification);
    final accent = _notifAccent(notification);
    final title = _notifTitle(notification);
    final message = _notifMessage(notification);
    final timeLabel = _notifFullTimeLabel(notification);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: LinqSpacing.s5,
          right: LinqSpacing.s5,
          top: LinqSpacing.s3,
          bottom: LinqSpacing.s5 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: LinqSpacing.s4),
                decoration: BoxDecoration(
                  color: LinqColors.borderDefault,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: LinqRadius.borderMd,
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: LinqSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: LinqTextStyles.h4
                            .copyWith(color: LinqColors.textPrimary),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeLabel,
                          style: LinqTextStyles.bodyXs
                              .copyWith(color: LinqColors.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LinqSpacing.s4),
            SelectableText(
              message,
              style: LinqTextStyles.body
                  .copyWith(color: LinqColors.textSecondary),
            ),
            const SizedBox(height: LinqSpacing.s5),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

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
              style:
                  LinqTextStyles.h4.copyWith(color: LinqColors.textPrimary),
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
