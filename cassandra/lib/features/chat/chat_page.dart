import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/firestore/models/chat_message_document.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _stickers = <String>[
    '⚽',
    '🔥',
    '👏',
    '😱',
    '😂',
    '❤️',
    '🏆',
    '💪',
  ];
  static const _maxImageBytes = 380000;

  final _inputController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;
    final text = _inputController.text.trim();
    if (fs == null || groupId == null || text.isEmpty || _sending) return;

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

  Future<void> _sendSticker(String sticker) async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;
    if (fs == null || groupId == null || _sending) return;

    setState(() => _sending = true);
    try {
      await fs.sendGroupChatMessage(
        groupId: groupId,
        senderUid: app.profile.id,
        senderDisplayName: app.profile.displayName,
        senderTeamName: app.profile.teamName,
        type: GroupChatMessageType.sticker,
        text: sticker,
      );
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

    final imageBase64 = base64Encode(bytes);
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

  Future<void> _showStickerPicker() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chatStickerPickerTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _stickers
                      .map((sticker) {
                        return FilledButton.tonal(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _sendSticker(sticker);
                          },
                          child: Text(
                            sticker,
                            style: const TextStyle(fontSize: 28),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final fs = app.firestoreService;
    final groupId = app.activeGroupId;

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
                          bottom: BorderSide(color: Color(0x1A000000)),
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
                      child: StreamBuilder<List<GroupChatMessageDocument>>(
                        stream: fs.streamGroupChatMessages(groupId: groupId),
                        builder: (context, snap) {
                          final cutoff = DateTime.now().toUtc().subtract(
                            const Duration(hours: 24),
                          );
                          final messages = (snap.data ?? const [])
                              .where((m) => m.createdAt.toUtc().isAfter(cutoff))
                              .toList(growable: false);

                          if (snap.connectionState == ConnectionState.waiting &&
                              messages.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          }
                          if (messages.isEmpty) {
                            return Center(
                              child: Text(
                                l10n.chatEmpty,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: CassandraColors.slate,
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final m = messages[index];
                              final mine = m.senderUid == app.profile.id;
                              return _ChatBubble(
                                message: m,
                                mine: mine,
                                timeLabel: _formatTime(m.createdAt.toLocal()),
                              );
                            },
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
                              tooltip: l10n.chatStickerPickerTitle,
                              onPressed: _sending ? null : _showStickerPicker,
                              icon: const Icon(Icons.emoji_emotions_outlined),
                            ),
                            IconButton(
                              tooltip: l10n.chatPhotoButton,
                              onPressed: _sending ? null : _pickAndSendImage,
                              icon: const Icon(Icons.photo_outlined),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _inputController,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onTapOutside: (_) =>
                                    FocusScope.of(context).unfocus(),
                                onSubmitted: (_) => _sendText(),
                                decoration: InputDecoration(
                                  hintText: l10n.chatInputHint,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
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
    final avatarBg = mine ? CassandraColors.primary : const Color(0xFFF1E6D1);
    final bubbleBg = mine ? CassandraColors.primary : const Color(0xFFF5F5F5);
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
                      ? const EdgeInsets.all(6)
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bubbleBg,
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
