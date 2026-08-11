# webview\_flutter\_wkwebview

The Apple WKWebView implementation of [`webview_flutter`][1].

## Upstream sync

This repository is maintained as an extracted mirror of:

`flutter/packages/packages/webview_flutter/webview_flutter_wkwebview`

That means this repository root maps to that subdirectory in the Flutter
monorepo.

### Pull latest upstream into local changes

If you have local commits and want to pull in newer upstream plugin changes:

1. Commit your local changes on a branch.
2. Regenerate/fetch the latest extracted upstream plugin branch from
   `flutter/packages`.
3. Rebase your branch onto that refreshed upstream branch (preferred), or merge
   it if you want to avoid history rewrite.

### Send changes back to Flutter upstream

Open upstream PRs from a `flutter/packages` branch, with your changes under:

`packages/webview_flutter/webview_flutter_wkwebview`

[1]: https://pub.dev/packages/webview_flutter
[2]: https://flutter.dev/to/endorsed-federated-plugin


## Usage

This package is [endorsed][2], which means you can simply use `webview_flutter`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

### External Native API

The plugin also provides a native API accessible by the native code of iOS applications or packages.
This API follows the convention of breaking changes of the Dart API, which means that any changes to
the class that are not backwards compatible will only be made with a major version change of the
plugin. Native code other than this external API does not follow breaking change conventions, so
app or plugin clients should not use any other native APIs.

The API can be accessed by importing the native plugin `webview_flutter_wkwebview`:

Objective-C:

```objectivec
@import webview_flutter_wkwebview;
```

Then you will have access to the native class `FWFWebViewFlutterWKWebViewExternalAPI`.

## Contributing

For information on contributing to this plugin, see [`CONTRIBUTING.md`](CONTRIBUTING.md).

