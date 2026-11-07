import 'dart:math' as math;

import 'package:flutter/material.dart';

Color sourceColor(String source) => switch (source) {
  'TioAnime' => const Color(0xffff527b),
  'AnimeFLV' => const Color(0xff42c8ff),
  'AnimeAV1' => const Color(0xffaf73ff),
  'MonosChinos1' => const Color(0xffffcd63),
  _ => const Color(0xff8b9bff),
};

Widget sourceBadge(String source) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
  decoration: BoxDecoration(
    color: const Color(0xee0c111d),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: sourceColor(source).withValues(alpha: .3)),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.layers_rounded, size: 11, color: sourceColor(source)),
      const SizedBox(width: 4),
      Text(
        source,
        style: TextStyle(
          fontSize: 10,
          color: sourceColor(source),
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
);

void showCompactNotice(BuildContext context, Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|FormatException|HttpException|SocketException):\s*'),
    '',
  );
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: math.min(420, MediaQuery.sizeOf(context).width - 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      backgroundColor: const Color(0xff202033),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xff403557)),
      ),
      duration: const Duration(seconds: 4),
      showCloseIcon: true,
      closeIconColor: const Color(0xffb6a7d8),
      content: Row(
        key: const ValueKey('compact-notice-content'),
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xffb69ae7),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xffece8f7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
