import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class PendingFile {
  PendingFile({
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String? contentType;

  MultipartFileEntry toEntry() => MultipartFileEntry(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
}

Future<List<PendingFile>> pickPmsFiles({
  bool allowMultiple = true,
  bool imagesOnly = false,
}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: allowMultiple,
    withData: true,
    type: imagesOnly ? FileType.image : FileType.any,
  );
  if (result == null) return const [];
  return result.files
      .where((f) => f.bytes != null)
      .map(
        (f) => PendingFile(
          bytes: f.bytes!,
          filename: f.name,
          contentType: null,
        ),
      )
      .toList();
}

Future<PendingFile?> pickCameraPhoto() async {
  final picker = ImagePicker();
  final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
  if (shot == null) return null;
  final bytes = await shot.readAsBytes();
  return PendingFile(
    bytes: bytes,
    filename: shot.name,
    contentType: 'image/jpeg',
  );
}

class MediaPickerBar extends StatelessWidget {
  const MediaPickerBar({
    super.key,
    required this.files,
    required this.onChanged,
  });

  final List<PendingFile> files;
  final ValueChanged<List<PendingFile>> onChanged;

  Future<void> _addFiles(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery / files'),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'camera') {
      final photo = await pickCameraPhoto();
      if (photo != null) onChanged([...files, photo]);
      return;
    }
    final picked = await pickPmsFiles();
    if (picked.isNotEmpty) onChanged([...files, ...picked]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => _addFiles(context),
          icon: const Icon(Icons.attach_file),
          label: Text(files.isEmpty ? 'Attach media' : 'Add more files (${files.length})'),
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...List.generate(files.length, (i) {
            final f = files[i];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(f.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  final next = [...files]..removeAt(i);
                  onChanged(next);
                },
              ),
            );
          }),
        ],
      ],
    );
  }
}

class MediaListPanel extends StatelessWidget {
  const MediaListPanel({
    super.key,
    required this.entity,
    this.onRemove,
    this.busy = false,
  });

  final Map<String, dynamic> entity;
  final Future<void> Function(String type, String url)? onRemove;
  final bool busy;

  List<_MediaItem> get _items {
    final out = <_MediaItem>[];
    void addAll(String type, dynamic list) {
      if (list is! List) return;
      for (final item in list) {
        final url = attachmentUrl(item);
        if (url.isEmpty) continue;
        out.add(_MediaItem(type: type, url: url, name: attachmentName(item)));
      }
    }

    addAll('photo', entity['photos']);
    addAll('video', entity['videos']);
    addAll('attachment', entity['attachments']);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No media yet', style: TextStyle(color: AppTheme.muted)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          leading: Icon(switch (item.type) {
            'photo' => Icons.image_outlined,
            'video' => Icons.videocam_outlined,
            _ => Icons.attach_file,
          }),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.type),
          onTap: () => launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication),
          trailing: onRemove == null
              ? null
              : IconButton(
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, color: AppTheme.danger),
                  onPressed: busy ? null : () => onRemove!(item.type, item.url),
                ),
        );
      },
    );
  }
}

class _MediaItem {
  const _MediaItem({
    required this.type,
    required this.url,
    required this.name,
  });

  final String type;
  final String url;
  final String name;
}

String attachmentUrl(dynamic item) {
  if (item == null) return '';
  if (item is String) return item;
  if (item is Map) return item['url']?.toString() ?? '';
  return '';
}

String attachmentName(dynamic item) {
  if (item == null) return 'file';
  if (item is String) {
    final path = item.split('?').first;
    return Uri.decodeComponent(path.split('/').last);
  }
  if (item is Map) {
    final name = item['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    return attachmentName(item['url']);
  }
  return 'file';
}
