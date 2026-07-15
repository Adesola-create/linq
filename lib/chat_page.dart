import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

/// Marks where a date separator belongs in the flattened message/date list.
class _DateMarker {
  final DateTime day;
  const _DateMarker(this.day);
}

class ChatPage extends StatefulWidget {
  final Map<String, dynamic> thread;
  const ChatPage({super.key, required this.thread});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;
  bool _loadingMore = false;
  bool _hasMoreMessages = true;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late Map<String, dynamic> _threadMeta;
  bool _otherIsTyping = false;
  Timer? _typingDebounce;
  Timer? _typingPollTimer;
  Timer? _messagePollTimer;

  String get _threadUlid {
    for (final key in ['ulid', 'thread_ulid', 'id']) {
      final v = widget.thread[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final nested = widget.thread['data'];
    if (nested is Map) {
      final v = nested['ulid']?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get _jobUlid => (widget.thread['job_ulid'] ?? '').toString();

  static const _photoKeys = [
    'photo_url', 'profile_photo', 'profile_photo_url',
    'avatar_url', 'image_url', 'image', 'avatar', 'picture',
  ];
  static const _nameKeys = [
    'name', 'full_name', 'business_name', 'display_name',
  ];

  Map<String, dynamic>? get _providerParticipant {
    // 1. participants array (handles any role casing)
    final participants =
        _threadMeta['participants'] ?? widget.thread['participants'];
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
    // 2. Top-level objects the API sometimes returns directly
    for (final key in ['provider', 'other_user', 'other_party', 'recipient']) {
      final v = _threadMeta[key] ?? widget.thread[key];
      if (v is Map) return v.cast<String, dynamic>();
    }
    return null;
  }

  String get _otherName {
    final p = _providerParticipant;
    if (p != null) {
      for (final key in _nameKeys) {
        final v = p[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    // Thread-level fallbacks
    for (final key in ['provider_name', 'other_name', 'name', 'title']) {
      final v = (_threadMeta[key] ?? widget.thread[key])?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return 'Provider';
  }

  String get _otherAvatar {
    final p = _providerParticipant;
    if (p != null) {
      for (final key in _photoKeys) {
        final v = p[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    // Thread-level fallbacks
    for (final key in ['provider_photo', 'provider_avatar', 'other_photo']) {
      final v = (_threadMeta[key] ?? widget.thread[key])?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _threadMeta = Map<String, dynamic>.from(widget.thread);
    _loadMessages();
    if (_threadUlid.isNotEmpty) {
      AuthService.markThreadRead(_threadUlid);
      _refreshThreadMeta();
      _startTypingPoll();
      _startMessagePoll();
    }
    _inputController.addListener(_onInputChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _typingPollTimer?.cancel();
    _messagePollTimer?.cancel();
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Reverse: true means scrolling "up" toward older history increases
  /// [pixels] toward [maxScrollExtent] — load the next page when near there.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadOlderMessages();
    }
  }

  /// Merges a fetched batch of server messages into [_messages], de-duping by
  /// id/ulid and re-sorting by `created_at` so paginated "older" batches and
  /// the polled "latest" window never conflict or leave gaps. Local messages
  /// that have already been confirmed `sent` are dropped here since the real
  /// server copy (now present in [incoming]) supersedes them.
  /// A stable identity for de-duping. Prefers a real id/ulid, but falls back
  /// to a content+timestamp composite so messages are never dropped just
  /// because the API didn't include an id field on that response.
  String _messageKey(Map<String, dynamic> m) {
    final id = m['id'] ?? m['ulid'] ?? m['local_id'];
    if (id != null) return 'id:$id';
    final content = m['body'] ??
        m['voice_note_url'] ??
        m['audio_url'] ??
        m['media_url'] ??
        '';
    return 'ts:${m['created_at']}|$content';
  }

  void _mergeServerMessages(List<Map<String, dynamic>> incoming) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final m in _messages) {
      if (m['local_id'] != null && m['_status'] == 'sent') continue;
      byKey[_messageKey(m)] = m;
    }
    for (final m in incoming) {
      byKey[_messageKey(m)] = m;
    }
    final merged = byKey.values.toList()
      ..sort((a, b) {
        final ta = DateTime.tryParse((a['created_at'] ?? '').toString());
        final tb = DateTime.tryParse((b['created_at'] ?? '').toString());
        if (ta == null || tb == null) return 0;
        return ta.compareTo(tb);
      });
    _messages = merged;
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || !_hasMoreMessages || _loading) return;
    setState(() => _loadingMore = true);
    final offset = _messages.where((m) => m['local_id'] == null).length;
    final result = await AuthService.getMessages(
      threadUlid: _threadUlid.isNotEmpty ? _threadUlid : null,
      jobUlid: _jobUlid.isNotEmpty ? _jobUlid : null,
      offset: offset,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>? ?? [];
      final older = raw.whereType<Map<String, dynamic>>().toList();
      setState(() {
        if (older.length < 50) _hasMoreMessages = false;
        _mergeServerMessages(older);
        _loadingMore = false;
      });
    } else {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refreshThreadMeta() async {
    final ulid = _threadUlid;
    if (ulid.isEmpty) return;
    final result = await AuthService.getThread(ulid);
    if (!mounted || result['success'] != true) return;
    final fresh = result['data'] as Map<String, dynamic>;
    setState(() {
      final merged = Map<String, dynamic>.from(_threadMeta)..addAll(fresh);
      if ((fresh['participants'] == null ||
              (fresh['participants'] as List?)?.isEmpty == true) &&
          _threadMeta['participants'] != null) {
        merged['participants'] = _threadMeta['participants'];
      }
      _threadMeta = merged;
      final typing = fresh['typing_users'] ?? fresh['typing'] ?? [];
      _otherIsTyping = typing is List && typing.isNotEmpty;
    });
  }

  void _startTypingPoll() {
    _typingPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshThreadMeta();
    });
  }

  /// Periodically refreshes the message list in the background so new
  /// messages from the other party appear without leaving the screen.
  void _startMessagePoll() {
    _messagePollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadMessages(silent: true);
    });
  }

  /// True when the user is already viewing the latest messages (the list is
  /// `reverse: true`, so the bottom of the conversation is scroll offset 0).
  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 80;
  }

  void _onInputChanged() {
    _typingDebounce?.cancel();
    final ulid = _threadUlid;
    if (ulid.isEmpty || _inputController.text.isEmpty) return;
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      AuthService.sendTypingIndicator(ulid);
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (mounted && !silent) setState(() { _loading = true; _error = null; });
    final result = await AuthService.getMessages(
      threadUlid: _threadUlid.isNotEmpty ? _threadUlid : null,
      jobUlid: _jobUlid.isNotEmpty ? _jobUlid : null,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>? ?? [];
      final msgs = raw.whereType<Map<String, dynamic>>().toList();
      // Decide before mutating state: jump to the new message only if the
      // user was already at the bottom, so reading older messages isn't
      // interrupted by background polling.
      final shouldScroll = !silent || _isNearBottom;
      setState(() {
        _mergeServerMessages(msgs);
        _loading = false;
      });
      if (shouldScroll) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom());
      }
      if (silent && _threadUlid.isNotEmpty) {
        AuthService.markThreadRead(_threadUlid);
      }
    } else {
      if (!silent) {
        setState(() {
          _loading = false;
          _error =
              result['message']?.toString() ?? 'Failed to load messages.';
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Adds [localMsg] to the conversation immediately (with `_status: pending`)
  /// so the UI updates instantly, then runs [send] in the background and
  /// updates the bubble's status once it resolves — mirrors WhatsApp's
  /// optimistic send/pending/sent/failed flow.
  Future<void> _sendOptimistic(
    Map<String, dynamic> localMsg,
    Future<Map<String, dynamic>> Function() send,
  ) async {
    setState(() => _messages.add(localMsg));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    final result = await send();
    _finishSend(localMsg['local_id'].toString(), result);
  }

  void _finishSend(String localId, Map<String, dynamic> result) {
    if (!mounted) return;
    final idx = _messages.indexWhere((m) => m['local_id'] == localId);
    if (idx == -1) return;
    if (result['success'] == true) {
      setState(() => _messages[idx]['_status'] = 'sent');
      _loadMessages(silent: true);
    } else {
      setState(() {
        _messages[idx]['_status'] = 'failed';
        _messages[idx]['_error'] =
            result['message']?.toString() ?? 'Failed to send.';
      });
    }
  }

  Future<void> _retrySend(Map<String, dynamic> msg) async {
    final localId = msg['local_id']?.toString();
    if (localId == null) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m['local_id'] == localId);
      if (idx != -1) _messages[idx]['_status'] = 'pending';
    });

    final kind = (msg['kind'] ?? '').toString();
    Map<String, dynamic> result;
    if (kind == 'voice') {
      final path = msg['local_path']?.toString();
      final duration = (msg['duration_seconds'] as num?)?.toInt() ?? 0;
      if (path == null || !await File(path).exists()) {
        if (!mounted) return;
        setState(() {
          final idx = _messages.indexWhere((m) => m['local_id'] == localId);
          if (idx != -1) {
            _messages[idx]['_status'] = 'failed';
            _messages[idx]['_error'] = 'Recording no longer available.';
          }
        });
        return;
      }
      final bytes = await File(path).readAsBytes();
      result = await AuthService.sendVoiceMessage(
        bytes: Uint8List.fromList(bytes),
        mimeType: 'audio/mp4',
        durationSeconds: duration,
        threadUlid: _threadUlid.isNotEmpty ? _threadUlid : null,
        jobUlid: _jobUlid.isNotEmpty ? _jobUlid : null,
      );
    } else {
      result = await AuthService.sendMessage(
        body: (msg['body'] ?? '').toString(),
        threadUlid: _threadUlid.isNotEmpty ? _threadUlid : null,
        jobUlid: _jobUlid.isNotEmpty ? _jobUlid : null,
      );
    }
    _finishSend(localId, result);
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    await _sendOptimistic(
      {
        'local_id': localId,
        'kind': 'text',
        'body': text,
        'sender_role': 'cust',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        '_status': 'pending',
      },
      () => AuthService.sendMessage(
        body: text,
        threadUlid: _threadUlid.isNotEmpty ? _threadUlid : null,
        jobUlid: _jobUlid.isNotEmpty ? _jobUlid : null,
      ),
    );
  }

  Future<void> _sendVoice(
    List<int> bytes,
    String mime,
    int durationSeconds,
    String localPath,
  ) async {
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    await _sendOptimistic(
      {
        'local_id': localId,
        'kind': 'voice',
        'sender_role': 'cust',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'local_path': localPath,
        '_status': 'pending',
      },
      () => AuthService.sendVoiceMessage(
        bytes: Uint8List.fromList(bytes),
        mimeType: mime,
        durationSeconds: durationSeconds,
        threadUlid: _threadUlid.isNotEmpty ? _threadUlid : null,
        jobUlid: _jobUlid.isNotEmpty ? _jobUlid : null,
      ),
    );
  }

  void _openProviderProfile() {
    final participant = _providerParticipant;
    final providerData = participant ??
        <String, dynamic>{'name': _otherName, 'photo_url': _otherAvatar};
    Navigator.pushNamed(
      context,
      '/provider-profile',
      arguments: {
        'provider': providerData,
        'showBottomNav': false,
        'hideHireActions': true,
      },
    );
  }

  /// Flattens [_messages] (chronological) into a display list that also
  /// includes a date-separator marker before the first message of each day,
  /// WhatsApp-style.
  List<dynamic> get _displayItems {
    final items = <dynamic>[];
    DateTime? lastDay;
    for (final m in _messages) {
      final created =
          DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal();
      if (created != null) {
        final day = DateTime(created.year, created.month, created.day);
        if (lastDay == null || day != lastDay) {
          items.add(_DateMarker(day));
          lastDay = day;
        }
      }
      items.add(m);
    }
    return items;
  }

  static String _formatDateMarker(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    final diff = today.difference(day).inDays;
    if (diff > 0 && diff < 7) {
      const weekdays = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ];
      return weekdays[day.weekday - 1];
    }
    return '${day.day}/${day.month}/${day.year}';
  }

  Widget _buildDateSeparator(DateTime day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LinqSpacing.s3),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: LinqColors.bgSurface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: LinqShadows.xs,
          ),
          child: Text(
            _formatDateMarker(day),
            style: LinqTextStyles.bodyXs.copyWith(
              color: LinqColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  bool _isMyMessage(Map<String, dynamic> msg) {
    final raw =
        (msg['sender_role'] ?? msg['sender_type'] ?? msg['from_role'] ?? '')
            .toString()
            .toLowerCase();
    return raw == 'cust' || raw == 'customer';
  }

  Widget _buildMessageList() {
    final displayItems = _displayItems;
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s4,
        vertical: LinqSpacing.s4,
      ),
      itemCount: displayItems.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= displayItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: LinqSpacing.s3),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LinqColors.forest500,
                ),
              ),
            ),
          );
        }
        final item = displayItems[displayItems.length - 1 - i];
        if (item is _DateMarker) {
          return _buildDateSeparator(item.day);
        }
        final msg = item as Map<String, dynamic>;
        final isMine = _isMyMessage(msg);
        final msgKey = (msg['id'] ??
                msg['ulid'] ??
                msg['local_id'] ??
                msg['created_at'] ??
                i)
            .toString();
        return _MessageBubble(
          key: ValueKey(msgKey),
          message: msg,
          isMine: isMine,
          senderName: isMine ? null : _otherName,
          senderAvatar: isMine ? null : _otherAvatar,
          onRetry: _retrySend,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _otherAvatar;
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openProviderProfile,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: LinqColors.forest400,
                backgroundImage: avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl.isEmpty
                    ? const Icon(Icons.person_rounded,
                        color: Colors.white, size: 18)
                    : null,
              ),
              const SizedBox(width: LinqSpacing.s3),
              Expanded(
                child: Text(
                  _otherName,
                  style: LinqTextStyles.h4
                      .copyWith(color: LinqColors.textOnBrand),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: LinqColors.forest500))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(LinqSpacing.s6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded,
                                  size: 48, color: LinqColors.stone300),
                              const SizedBox(height: LinqSpacing.s4),
                              Text(_error!,
                                  style: LinqTextStyles.bodySm.copyWith(
                                      color: LinqColors.textSecondary),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: LinqSpacing.s4),
                              OutlinedButton.icon(
                                onPressed: _loadMessages,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 56,
                                    color: LinqColors.stone300),
                                const SizedBox(height: LinqSpacing.s4),
                                Text('No messages yet',
                                    style: LinqTextStyles.h4.copyWith(
                                        color: LinqColors.textSecondary)),
                                const SizedBox(height: LinqSpacing.s2),
                                Text('Start the conversation below.',
                                    style: LinqTextStyles.bodySm.copyWith(
                                        color: LinqColors.textTertiary)),
                              ],
                            ),
                          )
                        : _buildMessageList(),
          ),
          if (_otherIsTyping)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s5,
                vertical: LinqSpacing.s2,
              ),
              color: LinqColors.bgSurface,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: LinqColors.forest100,
                    backgroundImage: _otherAvatar.isNotEmpty
                        ? CachedNetworkImageProvider(_otherAvatar)
                        : null,
                    child: _otherAvatar.isEmpty
                        ? const Icon(Icons.person_rounded,
                            size: 10, color: LinqColors.forest500)
                        : null,
                  ),
                  const SizedBox(width: LinqSpacing.s2),
                  Text(
                    '$_otherName is typing…',
                    style: LinqTextStyles.bodyXs.copyWith(
                      color: LinqColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          _InputBar(
            controller: _inputController,
            onSend: _sendMessage,
            onSendVoice: _sendVoice,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble — dispatches to _VoiceBubble for audio messages
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final String? senderName;
  final String? senderAvatar;
  final ValueChanged<Map<String, dynamic>>? onRetry;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderName,
    this.senderAvatar,
    this.onRetry,
  });

  bool get _isVoice {
    final kind =
        (message['kind'] ?? message['type'] ?? '').toString().toLowerCase();
    return kind == 'voice' || kind == 'audio';
  }

  String get _audioUrl =>
      (message['voice_note_url'] ??
              message['audio_url'] ??
              message['media_url'] ??
              message['body'] ??
              '')
          .toString();

  String get _body => (message['body'] ?? '').toString();

  /// Local send status — 'pending', 'sent', 'failed', or '' for messages
  /// that came from the server (no status indicator shown for those).
  String get _status => (message['_status'] ?? '').toString();

  String get _timeLabel {
    final raw = message['created_at']?.toString();
    if (raw == null) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusIcon(Color color) {
    switch (_status) {
      case 'pending':
        return Icon(Icons.access_time_rounded, size: 12, color: color);
      case 'sent':
        return Icon(Icons.done_rounded, size: 14, color: color);
      case 'failed':
        return GestureDetector(
          onTap: () => onRetry?.call(message),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 14, color: LinqColors.danger500),
              const SizedBox(width: 2),
              Text(
                'Retry',
                style: LinqTextStyles.bodyXs.copyWith(
                  color: LinqColors.danger500,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = senderAvatar ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s3),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: LinqColors.forest100,
              backgroundImage: avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl)
                  : null,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.person_rounded,
                      size: 16, color: LinqColors.forest500)
                  : null,
            ),
            const SizedBox(width: LinqSpacing.s2),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMine &&
                    senderName != null &&
                    senderName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: LinqSpacing.s1, bottom: 3),
                    child: Text(
                      senderName!,
                      style: LinqTextStyles.bodyXs.copyWith(
                        color: LinqColors.forest500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_isVoice)
                  _VoiceBubble(
                    url: _audioUrl,
                    localPath: message['local_path']?.toString(),
                    initialDurationSeconds:
                        (message['duration_seconds'] as num?)?.toInt() ?? 0,
                    isMine: isMine,
                    timeLabel: _timeLabel,
                    status: _status,
                    statusIcon:
                        isMine ? _buildStatusIcon : null,
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LinqSpacing.s4,
                      vertical: LinqSpacing.s3,
                    ),
                    decoration: BoxDecoration(
                      color: isMine
                          ? LinqColors.forest500
                          : LinqColors.bgSurface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft:
                            Radius.circular(isMine ? 16 : 4),
                        bottomRight:
                            Radius.circular(isMine ? 4 : 16),
                      ),
                      border: isMine
                          ? null
                          : Border.all(
                              color: LinqColors.borderDefault),
                      boxShadow: LinqShadows.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          _body,
                          style: LinqTextStyles.body.copyWith(
                            color: isMine
                                ? LinqColors.textOnBrand
                                : LinqColors.textPrimary,
                          ),
                        ),
                        if (_timeLabel.isNotEmpty || (isMine && _status.isNotEmpty)) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_timeLabel.isNotEmpty)
                                Text(
                                  _timeLabel,
                                  style: LinqTextStyles.bodyXs.copyWith(
                                    color: isMine
                                        ? LinqColors.textOnBrand
                                            .withValues(alpha: 0.7)
                                        : LinqColors.textTertiary,
                                  ),
                                ),
                              if (isMine && _status.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                _buildStatusIcon(LinqColors.textOnBrand
                                    .withValues(alpha: 0.7)),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 34),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voice message playback bubble
// ---------------------------------------------------------------------------

class _VoiceBubble extends StatefulWidget {
  final String url;
  final String? localPath;
  final int initialDurationSeconds;
  final bool isMine;
  final String timeLabel;
  final String status;
  final Widget Function(Color color)? statusIcon;

  const _VoiceBubble({
    required this.url,
    this.localPath,
    this.initialDurationSeconds = 0,
    required this.isMine,
    required this.timeLabel,
    this.status = '',
    this.statusIcon,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  // Once the audio source has been loaded, replays should just resume the
  // existing player instead of re-fetching/re-loading the file.
  bool _sourceLoaded = false;
  // Local cache of a remote voice note, so replays play from disk instead of
  // re-buffering over the network every time.
  String? _cachedFilePath;

  @override
  void initState() {
    super.initState();
    if (widget.initialDurationSeconds > 0) {
      _duration = Duration(seconds: widget.initialDurationSeconds);
    }
    // Without this, audioplayers releases the native player once playback
    // completes, so a second tap on "play" silently does nothing.
    _player.setReleaseMode(ReleaseMode.stop);
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      // Ignore zero/garbage durations reported for some streamed sources —
      // keep the duration_seconds value sent with the message instead.
      if (mounted && dur > Duration.zero) setState(() => _duration = dur);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
      return;
    }

    // Already loaded once — just resume/replay without re-fetching the file.
    if (_sourceLoaded) {
      try {
        if (_playerState == PlayerState.completed ||
            _playerState == PlayerState.stopped) {
          await _player.seek(Duration.zero);
        }
        await _player.resume();
        return;
      } catch (e) {
        print('[VoicePlay] resume() ERROR: $e');
        // Underlying player was released — fall through and reload it.
        _sourceLoaded = false;
      }
    }

    setState(() => _loading = true);
    try {
      Source? source;
      if (widget.localPath != null) {
        source = DeviceFileSource(widget.localPath!);
      } else if (widget.url.isNotEmpty) {
        final cachedPath = await _resolveLocalCachePath();
        source = cachedPath != null
            ? DeviceFileSource(cachedPath)
            : UrlSource(widget.url);
      }
      if (source == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      await _player.play(source);
      _sourceLoaded = true;
    } catch (e) {
      print('[VoicePlay] play() ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // Downloads a remote voice note to a local temp file the first time it's
  // played, then reuses that file on every subsequent replay so playback
  // starts instantly instead of re-buffering from the network.
  Future<String?> _resolveLocalCachePath() async {
    if (_cachedFilePath != null) return _cachedFilePath;
    try {
      final dir = await getTemporaryDirectory();
      final fileName = 'vn_${widget.url.hashCode.abs()}.cache';
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        _cachedFilePath = file.path;
        return _cachedFilePath;
      }
      final res = await http
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        await file.writeAsBytes(res.bodyBytes);
        _cachedFilePath = file.path;
        return _cachedFilePath;
      }
    } catch (e) {
      print('[VoicePlay] cache download ERROR: $e');
    }
    return null;
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;
    final total = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final current = _position.inMilliseconds.toDouble().clamp(0.0, total);
    final progress = current / total;

    final bg =
        widget.isMine ? LinqColors.forest500 : LinqColors.bgSurface;
    final fgSub = widget.isMine
        ? LinqColors.textOnBrand.withValues(alpha: 0.7)
        : LinqColors.textTertiary;
    final trackActive =
        widget.isMine ? Colors.white : LinqColors.forest500;
    final trackInactive = widget.isMine
        ? Colors.white.withValues(alpha: 0.35)
        : LinqColors.forest200;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LinqSpacing.s3, vertical: LinqSpacing.s3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMine ? 16 : 4),
          bottomRight: Radius.circular(widget.isMine ? 4 : 16),
        ),
        border: widget.isMine
            ? null
            : Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / pause button
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMine
                    ? Colors.white.withValues(alpha: 0.2)
                    : LinqColors.forest100,
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.isMine
                            ? Colors.white
                            : LinqColors.forest500,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: widget.isMine
                          ? Colors.white
                          : LinqColors.forest500,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: LinqSpacing.s2),
          // Waveform bars + progress
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Simulated waveform using a custom progress track
                SizedBox(
                  height: 28,
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      return _WaveformTrack(
                        progress: progress,
                        activeColor: trackActive,
                        inactiveColor: trackInactive,
                        width: constraints.maxWidth,
                        onSeek: (p) async {
                          final ms =
                              (p * _duration.inMilliseconds).round();
                          await _player.seek(
                              Duration(milliseconds: ms));
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _duration > Duration.zero
                          ? _fmt(_position)
                          : '0:00',
                      style: LinqTextStyles.bodyXs
                          .copyWith(color: fgSub, fontSize: 10),
                    ),
                    Row(
                      children: [
                        if (_duration > Duration.zero)
                          Text(
                            _fmt(_duration),
                            style: LinqTextStyles.bodyXs.copyWith(
                                color: fgSub, fontSize: 10),
                          ),
                        if (widget.timeLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            widget.timeLabel,
                            style: LinqTextStyles.bodyXs.copyWith(
                                color: fgSub, fontSize: 10),
                          ),
                        ],
                        if (widget.statusIcon != null &&
                            widget.status.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          widget.statusIcon!(fgSub),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Voice indicator icon
          Padding(
            padding:
                const EdgeInsets.only(left: LinqSpacing.s2),
            child: Icon(
              Icons.mic_rounded,
              size: 14,
              color: fgSub,
            ),
          ),
        ],
      ),
    );
  }
}

// Waveform-style progress track with simulated bars
class _WaveformTrack extends StatelessWidget {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double width;
  final ValueChanged<double> onSeek;

  const _WaveformTrack({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.width,
    required this.onSeek,
  });

  // Fixed bar heights — simulate a waveform pattern
  static const _heights = [
    0.4, 0.6, 0.9, 0.7, 0.5, 0.8, 1.0, 0.6, 0.4, 0.7,
    0.9, 0.5, 0.8, 0.6, 0.4, 0.7, 0.9, 1.0, 0.6, 0.5,
    0.8, 0.4, 0.7, 0.9, 0.5, 0.8, 0.6, 0.4, 0.9, 0.7,
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => onSeek(
          (d.localPosition.dx / width).clamp(0.0, 1.0)),
      child: CustomPaint(
        size: Size(width, 28),
        painter: _WaveformPainter(
          progress: progress,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          heights: _heights,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final List<double> heights;

  const _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.heights,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = heights.length;
    final barW = 3.0;
    final gap = (size.width - barW * n) / (n - 1);
    final maxH = size.height;
    final midY = maxH / 2;

    for (int i = 0; i < n; i++) {
      final x = i * (barW + gap);
      final h = maxH * heights[i];
      final isActive = i / n <= progress;
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barW / 2, midY),
            width: barW,
            height: h,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}

// ---------------------------------------------------------------------------
// Input bar with voice recording support
// ---------------------------------------------------------------------------

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Future<void> Function(
      List<int> bytes, String mime, int durationSeconds, String localPath) onSendVoice;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onSendVoice,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _sendingVoice = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    // Stop the recorder if still active before disposing (avoids stale-stop errors)
    if (_isRecording) {
      _recorder.stop().catchError((_) => null).whenComplete(_recorder.dispose);
    } else {
      _recorder.dispose();
    }
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Microphone permission is required to send voice messages.'),
          backgroundColor: LinqColors.danger500,
        ));
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopAndSend() async {
    if (!_isRecording) return; // guard against double-tap
    _recordTimer?.cancel();
    final duration = _recordSeconds;
    // Flip state immediately so the recording UI disappears before await
    setState(() { _isRecording = false; _sendingVoice = true; });
    final path = await _recorder.stop();
    if (mounted) setState(() => _sendingVoice = false);

    if (path != null && mounted) {
      final bytes = await File(path).readAsBytes();
      // Fire-and-forget: the chat page shows an optimistic "pending" bubble
      // and updates it to sent/failed once the upload finishes.
      widget.onSendVoice(bytes, 'audio/mp4', duration, path);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return; // guard against double-tap
    _recordTimer?.cancel();
    // Flip state immediately so cancel can't fire twice
    setState(() => _isRecording = false);
    final path = await _recorder.stop();
    if (path != null) {
      try { await File(path).delete(); } catch (_) {}
    }
  }

  String get _timerLabel {
    final m = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: LinqSpacing.s4,
        right: LinqSpacing.s4,
        top: LinqSpacing.s3,
        bottom: LinqSpacing.s3 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: LinqColors.bgSurface,
        border: Border(top: BorderSide(color: LinqColors.borderDefault)),
      ),
      child: SafeArea(
        top: false,
        child: _isRecording
            ? _buildRecordingBar()
            : _buildTextBar(),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Row(
      children: [
        // Cancel
        IconButton(
          onPressed: _cancelRecording,
          icon: const Icon(
            Icons.close_rounded,
            color: LinqColors.danger500,
          ),
          tooltip: 'Cancel',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: LinqSpacing.s3),
        // Animated pulse dot + timer
        Expanded(
          child: Row(
            children: [
              _PulseDot(),
              const SizedBox(width: LinqSpacing.s2),
              const Icon(Icons.mic_rounded,
                  color: LinqColors.danger500, size: 18),
              const SizedBox(width: LinqSpacing.s2),
              Text(
                _timerLabel,
                style: LinqTextStyles.body.copyWith(
                  color: LinqColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        // Send
        Material(
          color: LinqColors.forest500,
          borderRadius: LinqRadius.borderFull,
          child: InkWell(
            borderRadius: LinqRadius.borderFull,
            onTap: _sendingVoice ? null : _stopAndSend,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.send_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Type a message…',
              hintStyle: LinqTextStyles.body
                  .copyWith(color: LinqColors.textTertiary),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s4,
                vertical: LinqSpacing.s3,
              ),
              filled: true,
              fillColor: LinqColors.bgPageApp,
              border: OutlineInputBorder(
                borderRadius: LinqRadius.borderFull,
                borderSide:
                    const BorderSide(color: LinqColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: LinqRadius.borderFull,
                borderSide:
                    const BorderSide(color: LinqColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: LinqRadius.borderFull,
                borderSide: const BorderSide(
                    color: LinqColors.forest500, width: 1.5),
              ),
            ),
            onSubmitted: (_) => widget.onSend(),
          ),
        ),
        const SizedBox(width: LinqSpacing.s3),
        // Send text or mic button
        Material(
          color: _sendingVoice
              ? LinqColors.stone200
              : LinqColors.forest500,
          borderRadius: LinqRadius.borderFull,
          child: InkWell(
            borderRadius: LinqRadius.borderFull,
            onTap: _sendingVoice
                ? null
                : _hasText
                    ? widget.onSend
                    : _startRecording,
            child: SizedBox(
              width: 44,
              height: 44,
              child: _sendingVoice
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      _hasText
                          ? Icons.send_rounded
                          : Icons.mic_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// Pulsing red dot for recording indicator
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.3, end: 1.0).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: LinqColors.danger500,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
