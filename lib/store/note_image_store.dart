import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 记录楼层的图片存取。动图（GIF）原样复制以保留动画，
/// 其余图片超过 [maxSide] 时降尺寸压成 JPEG，避免原图动辄几十 MB
/// 把渲染内存吃光。文件放在应用私有目录 `masonry_todo/images/` 下，
/// 对外只以文件名引用。
class NoteImageStore {
  NoteImageStore({
    Future<Directory> Function()? directoryProvider,
    Random? random,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _random = random ?? Random();

  static const int maxSide = 1600;
  static const int jpegQuality = 82;

  /// GIF 原样保存，体积太大时拒绝（整块读进内存再解码会吃爆手机）。
  static const int maxGifBytes = 8 * 1024 * 1024;

  final Future<Directory> Function() _directoryProvider;
  final Random _random;

  Future<Directory> _dir() async {
    final base = await _directoryProvider();
    final dir = Directory('${base.path}/masonry_todo/images');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 把 [source] 处理进记录目录，返回文件名（可存入 Note.image）。
  /// 解码失败时原样复制，保证图片总能落库。
  Future<String> store(File source) async {
    final dir = await _dir();
    final Uint8List bytes = Uint8List.fromList(await source.readAsBytes());
    final bool isGif = source.path.toLowerCase().endsWith('.gif');
    if (isGif && bytes.length > maxGifBytes) {
      throw const FormatException('这张 GIF 太大，换一张小一点的');
    }

    Uint8List out = bytes;
    String ext = _extOf(source.path, '.bin');
    final img.Image? decoded = isGif ? null : img.decodeImage(bytes);
    if (decoded != null &&
        (decoded.width > maxSide || decoded.height > maxSide)) {
      final double scale = maxSide / max(decoded.width, decoded.height);
      final int w = (decoded.width * scale).round();
      final int h = (decoded.height * scale).round();
      // bakeOrientation 把 EXIF 方向烘进像素，手机竖拍不会躺倒。
      final img.Image baked = img.bakeOrientation(decoded);
      out = img.JpegEncoder(quality: jpegQuality).encode(
        img.copyResize(
          baked,
          width: w,
          height: h,
          interpolation: img.Interpolation.cubic,
        ),
        singleFrame: true,
      );
      ext = '.jpg';
    }

    final String name = _newName(ext);
    await File('${dir.path}/$name').writeAsBytes(out);
    return name;
  }

  /// [note.image] 对应的文件。
  Future<File> fileFor(String name) async {
    final dir = await _dir();
    return File('${dir.path}/$name');
  }

  /// 删除记录图片（todo 被删时清理）。文件不存在时静默。
  Future<void> deleteFile(String name) async {
    final file = await fileFor(name);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _newName(String ext) {
    final int ts = DateTime.now().microsecondsSinceEpoch;
    final int rand = _random.nextInt(0x7FFFFFFF);
    return '$ts-$rand$ext';
  }

  static String _extOf(String path, String fallback) {
    final int slash = path.lastIndexOf('/');
    final String file = slash >= 0 ? path.substring(slash + 1) : path;
    final int dot = file.lastIndexOf('.');
    if (dot <= 0) return fallback;
    return file.substring(dot);
  }
}
