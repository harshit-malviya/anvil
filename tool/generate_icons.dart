// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final masterFile = File('assets/icons/source/anvil_icon_master.png');
  if (!masterFile.existsSync()) {
    print('Error: Master icon file not found at ${masterFile.path}');
    exit(1);
  }

  final bytes = await masterFile.readAsBytes();
  final masterImage = img.decodeImage(bytes);
  if (masterImage == null) {
    print('Error: Could not decode master image PNG');
    exit(1);
  }

  print('Master image decoded: ${masterImage.width}x${masterImage.height}');

  // 1. Create transparent foreground by keying out background color #ECEAE4 (RGB: 236, 234, 228)
  final fgImage = img.Image.from(masterImage);
  const targetR = 236;
  const targetG = 234;
  const targetB = 228;

  for (int y = 0; y < fgImage.height; y++) {
    for (int x = 0; x < fgImage.width; x++) {
      final p = fgImage.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();

      final diffR = (r - targetR).abs();
      final diffG = (g - targetG).abs();
      final diffB = (b - targetB).abs();

      if (diffR < 18 && diffG < 18 && diffB < 18) {
        fgImage.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  // 2. Android Legacy Launcher Icons (ic_launcher.png)
  final legacySizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  for (final entry in legacySizes.entries) {
    final dir = Directory('android/app/src/main/res/${entry.key}');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final resized = img.copyResize(masterImage, width: entry.value, height: entry.value, interpolation: img.Interpolation.cubic);
    final file = File('${dir.path}/ic_launcher.png');
    await file.writeAsBytes(img.encodePng(resized));
    print('Wrote ${file.path} (${entry.value}x${entry.value})');
  }

  // 3. Android Adaptive Foreground Icons (ic_launcher_foreground.png)
  final adaptiveSizes = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
  };

  for (final entry in adaptiveSizes.entries) {
    final dir = Directory('android/app/src/main/res/${entry.key}');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final resizedFg = img.copyResize(fgImage, width: entry.value, height: entry.value, interpolation: img.Interpolation.cubic);
    final file = File('${dir.path}/ic_launcher_foreground.png');
    await file.writeAsBytes(img.encodePng(resizedFg));
    print('Wrote ${file.path} (${entry.value}x${entry.value})');
  }

  // 4. Play Store 512x512 Icon
  final playStoreDir = Directory('android/app/src/main');
  final playStoreResized = img.copyResize(masterImage, width: 512, height: 512, interpolation: img.Interpolation.cubic);
  final playStoreFile = File('${playStoreDir.path}/play_store_512.png');
  await playStoreFile.writeAsBytes(img.encodePng(playStoreResized));
  print('Wrote ${playStoreFile.path} (512x512)');

  // 5. In-App Mark (128x128 transparent)
  final assetsIconDir = Directory('assets/icons');
  if (!assetsIconDir.existsSync()) assetsIconDir.createSync(recursive: true);
  final markResized = img.copyResize(fgImage, width: 128, height: 128, interpolation: img.Interpolation.cubic);
  final markFile = File('${assetsIconDir.path}/anvil_mark.png');
  await markFile.writeAsBytes(img.encodePng(markResized));
  print('Wrote ${markFile.path} (128x128 transparent)');

  // 6. Windows Multi-Resolution app_icon.ico (256x256 max for ICO format)
  final master256 = img.copyResize(masterImage, width: 256, height: 256, interpolation: img.Interpolation.cubic);
  final icoBytes = img.encodeIco(master256);
  final icoFile = File('windows/runner/resources/app_icon.ico');
  if (!icoFile.parent.existsSync()) icoFile.parent.createSync(recursive: true);
  await icoFile.writeAsBytes(icoBytes);
  print('Wrote ${icoFile.path} (.ico file generated)');

  print('All icon assets generated successfully!');
}
