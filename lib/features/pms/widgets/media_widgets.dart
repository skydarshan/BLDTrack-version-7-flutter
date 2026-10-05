import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<PendingFile?> _pendingFromXFile(XFile shot) async {
  final bytes = await shot.readAsBytes();
  final name = shot.name.trim().isEmpty ? 'photo.jpg' : shot.name;
  final mime = shot.mimeType ?? (name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
  return PendingFile(bytes: bytes, filename: name, contentType: mime);
}

Future<PendingFile?> pickCameraPhoto() async {
  final picker = ImagePicker();
  final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
  if (shot == null) return null;
  return _pendingFromXFile(shot);
}

Future<List<PendingFile>> pickGalleryPhotos({bool allowMultiple = true}) async {
  final picker = ImagePicker();
  if (!allowMultiple) {
    final shot = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (shot == null) return const [];
    final file = await _pendingFromXFile(shot);
    return file == null ? const [] : [file];
  }
  final shots = await picker.pickMultiImage(imageQuality: 85);
  final out = <PendingFile>[];
  for (final shot in shots) {
    final file = await _pendingFromXFile(shot);
    if (file != null) out.add(file);
  }
  return out;
}

String mediaAccessMessage(PlatformException error) {
  final code = error.code.toLowerCase();
  final detail = (error.message ?? '').toLowerCase();
  if (code.contains('camera') || detail.contains('camera')) {
    return 'Camera is blocked. Allow camera for BldTrack in phone Settings, then try again.';
  }
  return 'Photos are blocked. Allow photos for BldTrack in phone Settings, then try again.';
}

void _showMediaMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
  );
}

/// Camera, gallery, or files. Permission denial stays on screen as a message.
Future<List<PendingFile>> showAttachmentPicker(
  BuildContext context, {
  bool allowMultiple = true,
}) async {
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
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Choose a file'),
            onTap: () => Navigator.pop(ctx, 'files'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return const [];
  try {
    if (choice == 'camera') {
      final photo = await pickCameraPhoto();
      return photo == null ? const [] : [photo];
    }
    if (choice == 'gallery') {
      return await pickGalleryPhotos(allowMultiple: allowMultiple);
    }
    return await pickPmsFiles(allowMultiple: allowMultiple);
  } on PlatformException catch (error) {
    if (context.mounted) _showMediaMessage(context, mediaAccessMessage(error));
    return const [];
  } catch (_) {
    if (context.mounted) {
      _showMediaMessage(context, 'Could not add the file. Try again.');
    }
    return const [];
  }
}

Future<void> openAttachment(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    _showMediaMessage(context, 'This file cannot be opened.');
    return;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showMediaMessage(context, 'Could not open the file. Try again.');
    }
  } catch (_) {
    if (context.mounted) {
      _showMediaMessage(context, 'Could not open the file. Try again.');
    }
  }
}

List<String> attachmentUrlsOf(dynamic raw) {
  if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
  if (raw is! List) return const [];
  return raw.map(attachmentUrl).where((url) => url.isNotEmpty).toList();
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
    final picked = await showAttachmentPicker(context);
    if (picked.isEmpty) return;
    onChanged([...files, ...picked]);
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
      separatorBuilder: (_, _) => const Divider(height: 1),
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
          onTap: () => openAttachment(context, item.url),
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
