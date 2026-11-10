import 'dart:io';

import 'package:path/path.dart' as p;

class AndroidProjectWorkspace {
  AndroidProjectWorkspace({required Directory root}) : root = root.absolute;

  final Directory root;

  static final RegExp _packagePattern =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');

  Future<Directory> createProject({
    required String name,
    required String packageId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 60 ||
        cleanName.contains('/') ||
        cleanName.contains(r'\') ||
        cleanName == '.' ||
        cleanName == '..') {
      throw ArgumentError.value(name, 'name', 'Invalid project name');
    }
    if (!_packagePattern.hasMatch(packageId)) {
      throw ArgumentError.value(packageId, 'packageId', 'Invalid Android package ID');
    }

    await root.create(recursive: true);
    final slug = cleanName.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) throw ArgumentError.value(name, 'name');

    final project = Directory(p.join(root.path, slug));
    if (await project.exists()) {
      throw FileSystemException('Project already exists', project.path);
    }

    final javaPath = packageId.split('.').join('/');
    final files = <String, String>{
      'settings.gradle': '''
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$cleanName"
include ':app'
''',
      'build.gradle': '''
plugins {
    id 'com.android.application' version '8.7.3' apply false
}
''',
      'gradle.properties': '''
org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8
android.useAndroidX=true
''',
      'app/build.gradle': '''
plugins {
    id 'com.android.application'
}

android {
    namespace '$packageId'
    compileSdk 35

    defaultConfig {
        applicationId '$packageId'
        minSdk 23
        targetSdk 35
        versionCode 1
        versionName '1.0'
    }
}
''',
      'app/src/main/AndroidManifest.xml': '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="$cleanName"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
      'app/src/main/java/$javaPath/MainActivity.java': '''
package $packageId;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView view = new TextView(this);
        view.setText("$cleanName");
        view.setTextSize(24);
        view.setPadding(32, 32, 32, 32);
        setContentView(view);
    }
}
''',
    };

    try {
      await project.create();
      for (final entry in files.entries) {
        final file = File(p.join(project.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value.trimLeft());
      }
      return project;
    } catch (_) {
      if (await project.exists()) await project.delete(recursive: true);
      rethrow;
    }
  }

  Future<File> _safeFile(Directory project, String relativePath) async {
    if (relativePath.trim().isEmpty || p.isAbsolute(relativePath)) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }

    final rootPath = p.normalize(root.absolute.path);
    final projectPath = p.normalize(project.absolute.path);
    if (!p.isWithin(rootPath, projectPath)) {
      throw ArgumentError('Project is outside workspace root');
    }

    final realProject = await project.resolveSymbolicLinks();
    final targetPath = p.normalize(p.join(realProject, relativePath));
    if (!p.isWithin(realProject, targetPath)) {
      throw ArgumentError('Path escapes project workspace');
    }

    return File(targetPath);
  }

  Future<void> writeTextFile(
    Directory project,
    String relativePath,
    String content,
  ) async {
    final file = await _safeFile(project, relativePath);
    await file.parent.create(recursive: true);

    final realParent = await file.parent.resolveSymbolicLinks();
    final realProject = await project.resolveSymbolicLinks();
    if (!p.isWithin(realProject, realParent)) {
      throw ArgumentError('File parent escapes project workspace');
    }

    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw ArgumentError('Symbolic links are not allowed');
    }
    await file.writeAsString(content);
  }

  Future<String> readTextFile(
    Directory project,
    String relativePath,
  ) async {
    final file = await _safeFile(project, relativePath);
    final realFile = await file.resolveSymbolicLinks();
    final realProject = await project.resolveSymbolicLinks();
    if (!p.isWithin(realProject, realFile)) {
      throw ArgumentError('File escapes project workspace');
    }
    return File(realFile).readAsString();
  }
}
