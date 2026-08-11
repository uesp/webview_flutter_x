# webview_flutter_x

UESP fork bundling Flutter WebView for our mobile apps:

- **Plus API** (`WebViewControllerPlus`) — local HTML/CSS/JS, scroll/click/resize bridges, padding helpers
- **Vendored** `webview_flutter` (path)
- **Android** fork (`webview_flutter_android/`)
- **Apple** fork (`wkwebview_flutter/`)

App dependency is this package only (path / submodule). Platform impls are pulled in via the path deps in `pubspec.yaml`.

```yaml
dependencies:
  webview_flutter_x:
    path: dependencies/webview_flutter_x
```

```dart
import 'package:webview_flutter_x/webview_flutter_x.dart';
```

Remote: https://github.com/uesp/webview_flutter_x

## Layout

```
lib/                     # webview_flutter_x public API
webview_flutter/         # stock webview_flutter (path)
webview_flutter_android/ # Android fork
wkwebview_flutter/       # Apple fork
example/
```

## History

This repository was renamed from `uesp/wkwebview_flutter`. The previous Apple-only root layout is kept on branch `archive/wk-root`.
