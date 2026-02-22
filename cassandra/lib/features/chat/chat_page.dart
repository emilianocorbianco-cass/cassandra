import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/firestore/models/chat_message_document.dart';
import '../../services/firestore/firestore_service.dart';

String _encodeImageBase64(Uint8List bytes) => base64Encode(bytes);

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with AutomaticKeepAliveClientMixin<ChatPage> {
  static const _maxImageBytes = 380000;
  static const _maxTextChars = 500;

  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _messagesController = ScrollController();
  String? _lastTailMessageId;
  bool _pendingScrollToBottom = false;
  bool _sending = false;
  FirestoreService? _boundStreamFirestore;
  String? _boundStreamGroupId;
  StreamSubscription<List<GroupChatMessageDocument>>? _messagesSub;
  List<GroupChatMessageDocument> _messages = const [];
  bool _messagesLoading = false;
  String _messagesSignature = '';
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(() {
      if (!_inputFocusNode.hasFocus) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animate: true);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMessagesBindingFromScope();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _inputFocusNode.dispose();
    _inputController.dispose();
    _messagesController.dispose();
    super.dispose();
  }

  void _syncMessagesBindingFromScope() {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;
    if (fs != null && groupId != null) {
      _bindMessagesStream(fs, groupId);
    } else {
      _unbindMessagesStream();
    }
  }

  Future<void> _sendText() async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;
    final trimmed = _inputController.text.trim();
    final text = trimmed.length > _maxTextChars
        ? trimmed.substring(0, _maxTextChars)
        : trimmed;
    if (fs == null || groupId == null || text.isEmpty || _sending) return;

    _pendingScrollToBottom = true;
    setState(() => _sending = true);
    try {
      await fs.sendGroupChatMessage(
        groupId: groupId,
        senderUid: app.profile.id,
        senderDisplayName: app.profile.displayName,
        senderTeamName: app.profile.teamName,
        type: GroupChatMessageType.text,
        text: text,
      );
      _inputController.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final l10n = AppLocalizations.of(context)!;
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;
    if (fs == null || groupId == null || _sending) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 65,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxImageBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.chatPhotoTooLarge)));
      return;
    }

    final imageBase64 = await compute(_encodeImageBase64, bytes);
    _pendingScrollToBottom = true;
    setState(() => _sending = true);
    try {
      await fs.sendGroupChatMessage(
        groupId: groupId,
        senderUid: app.profile.id,
        senderDisplayName: app.profile.displayName,
        senderTeamName: app.profile.teamName,
        type: GroupChatMessageType.image,
        imageBase64: imageBase64,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _isNearBottom() {
    if (!_messagesController.hasClients) return true;
    final position = _messagesController.position;
    return (position.maxScrollExtent - position.pixels) < 88;
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_messagesController.hasClients) return;
    final target = _messagesController.position.maxScrollExtent;
    if (animate) {
      _messagesController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      return;
    }
    _messagesController.jumpTo(target);
  }

  void _handleMessagesChanged(List<GroupChatMessageDocument> messages) {
    final tailId = messages.isNotEmpty ? messages.last.id : null;
    if (tailId == _lastTailMessageId && !_pendingScrollToBottom) return;

    final keepBottom = _pendingScrollToBottom || _isNearBottom();
    _pendingScrollToBottom = false;
    _lastTailMessageId = tailId;

    if (!keepBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(animate: true);
    });
  }

  void _bindMessagesStream(FirestoreService fs, String groupId) {
    if (_boundStreamFirestore == fs &&
        _boundStreamGroupId == groupId &&
        _messagesSub != null) {
      return;
    }

    final switchingGroup =
        _boundStreamGroupId != null && _boundStreamGroupId != groupId;

    _messagesSub?.cancel();
    _boundStreamFirestore = fs;
    _boundStreamGroupId = groupId;
    if (switchingGroup) {
      _messages = const [];
      _messagesSignature = '';
    }
    _messagesLoading = _messages.isEmpty;
    _lastTailMessageId = null;
    _pendingScrollToBottom = true;
    _messagesSub = fs
        .streamGroupChatMessages(groupId: groupId)
        .listen(
          (incoming) {
            final cutoff = DateTime.now().toUtc().subtract(
              const Duration(hours: 24),
            );
            final messages = incoming
                .where((m) => m.createdAt.toUtc().isAfter(cutoff))
                .toList(growable: false);

            final signature = _signatureFor(messages);
            final changed = signature != _messagesSignature;
            _handleMessagesChanged(messages);
            if (!mounted) return;
            if (!changed && !_messagesLoading) return;
            CassandraScope.of(context).clearBackendSyncError();
            setState(() {
              _messagesSignature = signature;
              _messages = messages;
              _messagesLoading = false;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted) return;
            CassandraScope.of(context).markBackendSyncError(error, stackTrace);
            setState(() {
              _messagesLoading = false;
            });
          },
        );
  }

  void _unbindMessagesStream() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _boundStreamFirestore = null;
    _boundStreamGroupId = null;
    _pendingScrollToBottom = false;
  }

  String _signatureFor(List<GroupChatMessageDocument> messages) {
    if (messages.isEmpty) return 'empty';
    final ids = messages.map((m) => m.id).join(',');
    return '${messages.length}|$ids';
  }

  String _formatTime(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;

    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible && !_keyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animate: true);
      });
    }
    _keyboardVisible = keyboardVisible;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.chatTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: (fs == null || groupId == null)
            ? _ChatLockedState(
                title: l10n.chatNoGroupTitle,
                subtitle: l10n.chatNoGroupSubtitle,
              )
            : GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: CassandraColors.dividerSoft),
                        ),
                      ),
                      child: Text(
                        l10n.chatEphemeralNotice,
                        style: const TextStyle(
                          color: CassandraColors.slate,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _messagesLoading && _messages.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _messages.isEmpty
                          ? Center(
                              child: Text(
                                l10n.chatEmpty,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: CassandraColors.slate,
                                ),
                              ),
                            )
                          : ListView.builder(
                              key: const PageStorageKey<String>(
                                'group_chat_messages',
                              ),
                              controller: _messagesController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                18,
                              ),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final m = _messages[index];
                                final mine = m.senderUid == app.profile.id;
                                return _ChatBubble(
                                  message: m,
                                  mine: mine,
                                  timeLabel: _formatTime(m.createdAt.toLocal()),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: l10n.chatPhotoButton,
                              onPressed: _sending ? null : _pickAndSendImage,
                              icon: const Icon(Icons.attach_file),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _inputController,
                                focusNode: _inputFocusNode,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onTapOutside: (_) =>
                                    FocusScope.of(context).unfocus(),
                                onSubmitted: (_) => _sendText(),
                                decoration: InputDecoration(
                                  hintText: l10n.chatInputHint,
                                  isDense: false,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                    borderSide: const BorderSide(
                                      color: CassandraColors.chatInputBorderIdle,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(28),
                                    borderSide: const BorderSide(
                                      color: CassandraColors.primary,
                                      width: 1.2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _sending ? null : _sendText,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _ChatLockedState extends StatelessWidget {
  const _ChatLockedState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 44),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CassandraColors.slate),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.mine,
    required this.timeLabel,
  });

  final GroupChatMessageDocument message;
  final bool mine;
  final String timeLabel;

  Uint8List? _decodeImageBytes(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      return base64Decode(source);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final avatarBg = mine ? CassandraColors.primary : CassandraColors.chatOtherAvatarBg;
    final bubbleBg = mine ? CassandraColors.primary : CassandraColors.cardBg;
    const imageBubbleBg = CassandraColors.chatImageBubbleBg;
    final imageBorderColor = mine
        ? CassandraColors.primary.withValues(alpha: 0.6)
        : CassandraColors.primary.withValues(alpha: 0.26);
    final bubbleFg = mine ? CassandraColors.onPrimary : Colors.black87;
    final imageBytes = _decodeImageBytes(message.imageBase64);

    Widget content;
    switch (message.type) {
      case GroupChatMessageType.image:
        content = imageBytes == null
            ? const SizedBox.shrink()
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        insetPadding: const EdgeInsets.all(16),
                        child: InteractiveViewer(
                          child: Image.memory(imageBytes, fit: BoxFit.contain),
                        ),
                      ),
                    );
                  },
                  child: Image.memory(
                    imageBytes,
                    width: 190,
                    fit: BoxFit.cover,
                  ),
                ),
              );
        break;
      case GroupChatMessageType.sticker:
        content = Text(
          (message.text ?? '🙂').trim(),
          style: const TextStyle(fontSize: 34),
        );
        break;
      case GroupChatMessageType.text:
        content = Text(
          message.text ?? '',
          style: TextStyle(color: bubbleFg, fontWeight: FontWeight.w500),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Text(
                message.senderLabel,
                style: const TextStyle(
                  color: CassandraColors.slate,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine)
                CircleAvatar(
                  radius: 12,
                  backgroundColor: avatarBg,
                  child: Text(
                    message.senderLabel.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: mine
                          ? CassandraColors.onPrimary
                          : CassandraColors.primary,
                    ),
                  ),
                ),
              if (!mine) const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: message.type == GroupChatMessageType.image
                      ? const EdgeInsets.all(2)
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: message.type == GroupChatMessageType.image
                        ? imageBubbleBg
                        : bubbleBg,
                    border: message.type == GroupChatMessageType.image
                        ? Border.all(color: imageBorderColor, width: 1)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: content,
                ),
              ),
              if (mine) const SizedBox(width: 6),
              Text(
                timeLabel,
                style: const TextStyle(
                  color: CassandraColors.slate,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
