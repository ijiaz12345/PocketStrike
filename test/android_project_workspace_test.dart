import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketstrike/features/app_builder/data/android_project_workspace.dart';

void main() {
  late Directory tempRoot;
  late AndroidProjectWorkspace workspace;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pocketstrike_workspace_');
    workspace = AndroidProjectWorkspace(root: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('creates Android project structure', () async {
    final project = await workspace.createProject(
      name: 'Weather Demo',
      packageId: 'com.example.weatherdemo',
    );

    expect(await File('${project.path}/settings.gradle').exists(), isTrue);
    expect(await File('${project.path}/app/build.gradle').exists(), isTrue);
    expect(
      await File('${project.path}/app/src/main/AndroidManifest.xml').exists(),
      isTrue,
    );
  });

  test('rejects invalid package identifiers', () {
    expect(
      () => workspace.createProject(
        name: 'Bad App',
        packageId: 'not a package',
      ),
      throwsArgumentError,
    );
  });

  test('rejects duplicate project names', () async {
    await workspace.createProject(
      name: 'Notes',
      packageId: 'com.example.notes',
    );

    expect(
      () => workspace.createProject(
        name: 'Notes',
        packageId: 'com.example.notes2',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('supports project file read and write', () async {
    final project = await workspace.createProject(
      name: 'Notes',
      packageId: 'com.example.notes',
    );

    await workspace.writeTextFile(
      project,
      'app/src/main/assets/readme.txt',
      'hello',
    );

    expect(
      await workspace.readTextFile(
        project,
        'app/src/main/assets/readme.txt',
      ),
      'hello',
    );
  });

  test('blocks path traversal', () async {
    final project = await workspace.createProject(
      name: 'Notes',
      packageId: 'com.example.notes',
    );

    expect(
      () => workspace.writeTextFile(project, '../outside.txt', 'blocked'),
      throwsArgumentError,
    );
  });
}
