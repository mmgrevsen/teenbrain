// Adds the hand-written macOS sources under macos/Runner/GlemtDet to the Xcode
// project. `flutter create` only knows about the files it generated, and an
// Xcode project lists every source explicitly, so new native code has to be
// registered here or it silently never compiles.
//
// The file list is read from disk rather than hard-coded: a hard-coded list
// goes stale the moment someone adds a .swift file, and the failure mode is a
// file that quietly never builds. Registration is per-file and idempotent, so
// running it after adding one source registers exactly that one.
//
//   dart tool/add_native_sources.dart

import 'dart:io';

const groupName = 'GlemtDet';
const sourceDir = 'macos/Runner/GlemtDet';
const projectPath = 'macos/Runner.xcodeproj/project.pbxproj';
const groupId = '4713000000000000000002AA';

/// Deterministic 24-character object ids, derived from the file name so that
/// re-running produces an identical project file and a diff stays readable.
String _id(String name, int salt) {
  var hash = salt;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return '4713${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}'
      '${salt.toString().padLeft(2, '0')}${'0' * 10}'
      .substring(0, 24);
}

String fileRefId(String name) => _id(name, 1);
String buildFileId(String name) => _id(name, 2);

void main() {
  final project = File(projectPath);
  if (!project.existsSync()) {
    stderr.writeln('Kunne ikke finde $projectPath — kør scriptet fra projektroden.');
    exit(1);
  }

  final directory = Directory(sourceDir);
  if (!directory.existsSync()) {
    stderr.writeln('Kunne ikke finde $sourceDir.');
    exit(1);
  }

  final sources = directory
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((name) => name.endsWith('.swift'))
      .toList()
    ..sort();

  if (sources.isEmpty) {
    stdout.writeln('Der er ingen Swift-filer i $sourceDir.');
    return;
  }

  var text = project.readAsStringSync();

  if (!text.contains(groupId)) {
    text = _createGroup(text, sources);
    project.writeAsStringSync(text);
    stdout.writeln('Oprettede gruppen og tilføjede ${sources.length} native kilder.');
    return;
  }

  final missing = sources
      .where((name) => !text.contains('/* $name */ = {isa = PBXFileReference'))
      .toList();

  if (missing.isEmpty) {
    stdout.writeln('De native kilder er allerede registreret i Xcode-projektet.');
    return;
  }

  for (final name in missing) {
    text = _register(text, name);
  }

  project.writeAsStringSync(text);
  stdout.writeln('Tilføjede ${missing.length} native '
      '${missing.length == 1 ? 'kilde' : 'kilder'}: ${missing.join(', ')}');
}

/// First run: build the whole group in one pass.
String _createGroup(String text, List<String> sources) {
  final buildFiles = StringBuffer();
  final fileRefs = StringBuffer();
  final children = StringBuffer();
  final compile = StringBuffer();

  for (final name in sources) {
    buildFiles.writeln(
      '\t\t${buildFileId(name)} /* $name in Sources */ = '
      '{isa = PBXBuildFile; fileRef = ${fileRefId(name)} /* $name */; };',
    );
    fileRefs.writeln(
      '\t\t${fileRefId(name)} /* $name */ = {isa = PBXFileReference; '
      'lastKnownFileType = sourcecode.swift; path = $name; sourceTree = "<group>"; };',
    );
    children.writeln('\t\t\t\t${fileRefId(name)} /* $name */,');
    compile.writeln('\t\t\t\t${buildFileId(name)} /* $name in Sources */,');
  }

  var text2 = _insertAfter(text, '/* Begin PBXBuildFile section */\n', buildFiles.toString());
  text2 = _insertAfter(text2, '/* Begin PBXFileReference section */\n', fileRefs.toString());

  final group = StringBuffer()
    ..writeln('\t\t$groupId /* $groupName */ = {')
    ..writeln('\t\t\tisa = PBXGroup;')
    ..writeln('\t\t\tchildren = (')
    ..write(children)
    ..writeln('\t\t\t);')
    ..writeln('\t\t\tpath = $groupName;')
    ..writeln('\t\t\tsourceTree = "<group>";')
    ..writeln('\t\t};');
  text2 = _insertAfter(text2, '/* Begin PBXGroup section */\n', group.toString());

  text2 = _insertAfter(
    text2,
    '\t\t\t\t33CC11122044BFA00003C045 /* MainFlutterWindow.swift */,\n',
    '\t\t\t\t$groupId /* $groupName */,\n',
  );

  return _insertAfter(
    text2,
    '\t\t\t\t33CC11132044BFA00003C045 /* MainFlutterWindow.swift in Sources */,\n',
    compile.toString(),
  );
}

/// Later runs: slot one file into the four places it has to appear.
String _register(String text, String name) {
  var out = _insertAfter(
    text,
    '/* Begin PBXBuildFile section */\n',
    '\t\t${buildFileId(name)} /* $name in Sources */ = '
    '{isa = PBXBuildFile; fileRef = ${fileRefId(name)} /* $name */; };\n',
  );

  out = _insertAfter(
    out,
    '/* Begin PBXFileReference section */\n',
    '\t\t${fileRefId(name)} /* $name */ = {isa = PBXFileReference; '
    'lastKnownFileType = sourcecode.swift; path = $name; sourceTree = "<group>"; };\n',
  );

  out = _insertAfter(
    out,
    '\t\t$groupId /* $groupName */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n',
    '\t\t\t\t${fileRefId(name)} /* $name */,\n',
  );

  return _insertAfter(
    out,
    '\t\t\t\t33CC11132044BFA00003C045 /* MainFlutterWindow.swift in Sources */,\n',
    '\t\t\t\t${buildFileId(name)} /* $name in Sources */,\n',
  );
}

String _insertAfter(String text, String anchor, String insertion) {
  final index = text.indexOf(anchor);
  if (index < 0) {
    stderr.writeln('Kunne ikke finde ankeret i project.pbxproj:\n$anchor');
    exit(1);
  }
  final at = index + anchor.length;
  return text.substring(0, at) + insertion + text.substring(at);
}
