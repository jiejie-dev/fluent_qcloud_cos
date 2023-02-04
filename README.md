<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

一个纯dart的腾讯云对象存储的包.

## Features

- 分快上传功能.

## Usage

```dart
await FluentQCloudCos.putObject(
      ObjectStoragePutObjectRequest(
        taskId: "putObjectFileSizeMoreThan20M",
        filePath: largeFilePath,
        bucketName: bucketName!,
        objectName: "file-small.jpg",
        accessKeyId: secretId!,
        accessKeySecret: secretKey!,
        securityToken: "",
        expiredTime:
            DateTime.now().add(const Duration(days: 50)).millisecondsSinceEpoch,
        region: region!,
      ),
    );
```

