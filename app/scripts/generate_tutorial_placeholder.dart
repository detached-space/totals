import 'dart:async';
import 'dart:io';

// Tutorial videos are displayed at this width in the feature preview sheet.
// Keeping the placeholder at the same width avoids blocky upscaling while the
// video player is initializing.
const int _defaultWidth = 876;
const double _defaultBlurSigma = 20;
const int _defaultQuality = 45;

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    if (options.showHelp) {
      _printUsage();
      return;
    }

    await _generatePlaceholder(options);
  } on _UsageException catch (error) {
    stderr.writeln('Error: ${error.message}\n');
    _printUsage(toStderr: true);
    exitCode = 64;
  } on _GenerationException catch (error) {
    stderr.writeln('Error: ${error.message}');
    exitCode = 1;
  } on ProcessException catch (error) {
    stderr.writeln(
      'Could not run ffmpeg. Install FFmpeg and make sure ffmpeg is on '
      'your PATH.\n${error.message}',
    );
    exitCode = 69;
  } on FileSystemException catch (error) {
    stderr.writeln('File error: ${error.message}');
    if (error.path != null) {
      stderr.writeln('Path: ${error.path}');
    }
    exitCode = 74;
  }
}

Future<void> _generatePlaceholder(_Options options) async {
  final inputFile = File(options.inputPath!).absolute;
  if (!inputFile.existsSync()) {
    throw _UsageException('Input video does not exist: ${inputFile.path}');
  }

  final featureName = _slugify(
    options.featureName ?? _basenameWithoutExtension(inputFile.path),
  );
  if (featureName.isEmpty) {
    throw const _UsageException(
      'The feature name must contain at least one letter or number.',
    );
  }

  final usesDefaultOutput = options.outputPath == null;
  final outputFile = usesDefaultOutput
      ? File(
          _join(<String>[
            _findAppRoot().path,
            'assets',
            'images',
            'tutorials',
            '${featureName}_blurred.webp',
          ]),
        )
      : File(options.outputPath!).absolute;

  if (!outputFile.path.toLowerCase().endsWith('.webp')) {
    throw const _UsageException('The output path must end with .webp.');
  }

  if (outputFile.existsSync() && !options.force) {
    throw _UsageException(
      'Output already exists: ${outputFile.path}\n'
      'Run the command again with --force to replace it.',
    );
  }

  await outputFile.parent.create(recursive: true);
  final temporaryFile = File(
    '${outputFile.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}.webp',
  );
  final blurSigma = options.blurSigma.toStringAsFixed(
    options.blurSigma == options.blurSigma.roundToDouble() ? 0 : 2,
  );
  final ffmpegArguments = <String>[
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-ss',
    '0',
    '-i',
    inputFile.path,
    '-frames:v',
    '1',
    '-an',
    '-vf',
    'scale=${options.width}:-2:flags=lanczos,'
        'gblur=sigma=$blurSigma',
    '-c:v',
    'libwebp',
    '-quality',
    options.quality.toString(),
    '-compression_level',
    '6',
    temporaryFile.path,
  ];

  stdout.writeln('Generating blurred placeholder...');
  final process = await Process.start(
    'ffmpeg',
    ffmpegArguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final ffmpegExitCode = await process.exitCode;
  if (ffmpegExitCode != 0 ||
      !temporaryFile.existsSync() ||
      temporaryFile.lengthSync() == 0) {
    if (temporaryFile.existsSync()) {
      await temporaryFile.delete();
    }
    throw _GenerationException(
      'FFmpeg failed to generate the placeholder (exit code '
      '$ffmpegExitCode).',
    );
  }

  // Keep the previous asset intact until FFmpeg has produced a valid new file.
  if (outputFile.existsSync() && !options.force) {
    await temporaryFile.delete();
    throw _UsageException(
      'Output was created while FFmpeg was running: ${outputFile.path}\n'
      'Run the command again with --force if you want to replace it.',
    );
  }
  if (outputFile.existsSync()) {
    await outputFile.delete();
  }
  await temporaryFile.rename(outputFile.path);

  stdout.writeln('Created: ${outputFile.path}');
  stdout.writeln('Size: ${outputFile.lengthSync()} bytes');
  if (usesDefaultOutput) {
    stdout.writeln(
      "videoPlaceholderAsset: "
      "'assets/images/tutorials/${featureName}_blurred.webp',",
    );
  }
}

class _Options {
  const _Options({
    required this.inputPath,
    required this.featureName,
    required this.outputPath,
    required this.width,
    required this.blurSigma,
    required this.quality,
    required this.force,
    required this.showHelp,
  });

  factory _Options.parse(List<String> arguments) {
    String? inputPath;
    String? featureName;
    String? outputPath;
    var width = _defaultWidth;
    var blurSigma = _defaultBlurSigma;
    var quality = _defaultQuality;
    var force = false;
    var showHelp = false;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];

      String readValue() {
        if (index + 1 >= arguments.length) {
          throw _UsageException('Missing value after $argument.');
        }
        index++;
        return arguments[index];
      }

      switch (argument) {
        case '--input':
        case '-i':
          inputPath = readValue();
          break;
        case '--name':
        case '-n':
          featureName = readValue();
          break;
        case '--output':
        case '-o':
          outputPath = readValue();
          break;
        case '--width':
          width = int.tryParse(readValue()) ?? -1;
          break;
        case '--blur':
          blurSigma = double.tryParse(readValue()) ?? -1;
          break;
        case '--quality':
          quality = int.tryParse(readValue()) ?? -1;
          break;
        case '--force':
        case '-f':
          force = true;
          break;
        case '--help':
        case '-h':
          showHelp = true;
          break;
        default:
          throw _UsageException('Unknown option: $argument');
      }
    }

    if (!showHelp && (inputPath == null || inputPath.trim().isEmpty)) {
      throw const _UsageException('Provide a video with --input.');
    }
    if (width < 16 || width > 2048) {
      throw const _UsageException('--width must be between 16 and 2048.');
    }
    if (!blurSigma.isFinite || blurSigma <= 0 || blurSigma > 100) {
      throw const _UsageException(
          '--blur must be greater than 0 and at most 100.');
    }
    if (quality < 0 || quality > 100) {
      throw const _UsageException('--quality must be between 0 and 100.');
    }

    return _Options(
      inputPath: inputPath,
      featureName: featureName,
      outputPath: outputPath,
      width: width,
      blurSigma: blurSigma,
      quality: quality,
      force: force,
      showHelp: showHelp,
    );
  }

  final String? inputPath;
  final String? featureName;
  final String? outputPath;
  final int width;
  final double blurSigma;
  final int quality;
  final bool force;
  final bool showHelp;
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

class _GenerationException implements Exception {
  const _GenerationException(this.message);

  final String message;
}

Directory _findAppRoot() {
  final currentDirectory = Directory.current;
  if (File(_join(<String>[currentDirectory.path, 'pubspec.yaml']))
      .existsSync()) {
    return currentDirectory;
  }

  final scriptDirectory = File.fromUri(Platform.script).parent;
  final scriptParent = scriptDirectory.parent;
  if (File(_join(<String>[scriptParent.path, 'pubspec.yaml'])).existsSync()) {
    return scriptParent;
  }

  throw const _UsageException(
    'Could not locate app/pubspec.yaml. Run this command from the app folder.',
  );
}

String _basenameWithoutExtension(String path) {
  final filename = path.replaceAll('\\', '/').split('/').last;
  final extensionIndex = filename.lastIndexOf('.');
  return extensionIndex <= 0 ? filename : filename.substring(0, extensionIndex);
}

String _slugify(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

String _join(List<String> parts) => parts.join(Platform.pathSeparator);

void _printUsage({bool toStderr = false}) {
  const usage = '''
Generate a blurred first-frame placeholder for a tutorial video.

Usage:
  dart scripts/generate_tutorial_placeholder.dart --input <video> [options]

Options:
  -i, --input <path>     Source video (required)
  -n, --name <name>      Feature name used for the asset filename
  -o, --output <path>    Override the output path
      --width <pixels>   Output width (default: 876)
      --blur <sigma>     Blur strength (default: 20)
      --quality <0-100>  WebP quality (default: 45)
  -f, --force            Replace an existing output file
  -h, --help             Show this help

Example:
  dart scripts/generate_tutorial_placeholder.dart --input ..\\test-motion.mp4 --name auto_categorization

Default output:
  assets/images/tutorials/<name>_blurred.webp
''';

  if (toStderr) {
    stderr.write(usage);
  } else {
    stdout.write(usage);
  }
}
