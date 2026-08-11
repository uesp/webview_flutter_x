// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.webviewflutter;

import android.annotation.SuppressLint;
import android.content.Context;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewParent;
import android.webkit.DownloadListener;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.embedding.android.FlutterView;
import io.flutter.plugin.platform.PlatformView;
import java.util.Map;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * Host api implementation for {@link WebView}.
 *
 * <p>Handles creating {@link WebView}s that intercommunicate with a paired Dart object.
 */
public class WebViewProxyApi extends PigeonApiWebView {
  /** Implementation of {@link WebView} that can be used as a Flutter {@link PlatformView}s. */
  @SuppressLint("ViewConstructor")
  public static class WebViewPlatformView extends WebView implements PlatformView {
    private final WebViewProxyApi api;

    private WebViewClient currentWebViewClient;

    private WebChromeClientProxyApi.SecureWebChromeClient currentWebChromeClient;

    private boolean scrollGestureListening = false;
    private boolean consumeScrollGestures = false;
    private boolean scrollGestureActive = false;
    private final GestureDetector scrollGestureDetector;

    WebViewPlatformView(@NonNull WebViewProxyApi api) {
      super(api.getPigeonRegistrar().getContext());
      this.api = api;
      currentWebViewClient = new WebViewClient();
      currentWebChromeClient = new WebChromeClientProxyApi.SecureWebChromeClient();

      setWebViewClient(currentWebViewClient);
      setWebChromeClient(currentWebChromeClient);

      scrollGestureDetector =
          new GestureDetector(
              api.getPigeonRegistrar().getContext(),
              new GestureDetector.SimpleOnGestureListener() {
                @Override
                public boolean onDown(@NonNull MotionEvent e) {
                  return scrollGestureListening;
                }

                @Override
                public boolean onScroll(
                    @Nullable MotionEvent e1,
                    @NonNull MotionEvent e2,
                    float distanceX,
                    float distanceY) {
                  if (!scrollGestureListening) {
                    return false;
                  }
                  final float localX = e2.getX();
                  final float localY = e2.getY();
                  final float[] global = toFlutterGlobal(localX, localY);
                  // GestureDetector distance is opposite of finger delta; invert.
                  final float deltaX = -distanceX;
                  final float deltaY = -distanceY;
                  if (!scrollGestureActive) {
                    scrollGestureActive = true;
                    reportScrollGesture(
                        ScrollGesturePhase.START,
                        e2.getEventTime() / 1000.0,
                        global[0],
                        global[1],
                        localX,
                        localY,
                        0,
                        0,
                        0,
                        0);
                  }
                  reportScrollGesture(
                      ScrollGesturePhase.UPDATE,
                      e2.getEventTime() / 1000.0,
                      global[0],
                      global[1],
                      localX,
                      localY,
                      deltaX,
                      deltaY,
                      0,
                      0);
                  return consumeScrollGestures;
                }

                @Override
                public boolean onFling(
                    @Nullable MotionEvent e1,
                    @NonNull MotionEvent e2,
                    float velocityX,
                    float velocityY) {
                  if (!scrollGestureListening || !scrollGestureActive) {
                    return false;
                  }
                  final float localX = e2.getX();
                  final float localY = e2.getY();
                  final float[] global = toFlutterGlobal(localX, localY);
                  scrollGestureActive = false;
                  reportScrollGesture(
                      ScrollGesturePhase.END,
                      e2.getEventTime() / 1000.0,
                      global[0],
                      global[1],
                      localX,
                      localY,
                      0,
                      0,
                      velocityX,
                      velocityY);
                  return consumeScrollGestures;
                }
              });

      setOnTouchListener(
          (v, event) -> {
            if (!scrollGestureListening) {
              return false;
            }
            final boolean handled = scrollGestureDetector.onTouchEvent(event);
            final int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
              if (scrollGestureActive) {
                final float localX = event.getX();
                final float localY = event.getY();
                final float[] global = toFlutterGlobal(localX, localY);
                final ScrollGesturePhase phase =
                    action == MotionEvent.ACTION_CANCEL
                        ? ScrollGesturePhase.CANCEL
                        : ScrollGesturePhase.END;
                scrollGestureActive = false;
                reportScrollGesture(
                    phase,
                    event.getEventTime() / 1000.0,
                    global[0],
                    global[1],
                    localX,
                    localY,
                    0,
                    0,
                    0,
                    0);
              }
            }
            // When consuming, claim move sequences so the WebView does not scroll;
            // still allow the WebView to see taps (unhandled downs without scroll).
            if (consumeScrollGestures && scrollGestureActive) {
              return true;
            }
            return handled && consumeScrollGestures;
          });
    }

    void setScrollGestureListening(boolean enabled, boolean consume) {
      scrollGestureListening = enabled;
      consumeScrollGestures = consume;
      if (!enabled) {
        scrollGestureActive = false;
      }
    }

    private float[] toFlutterGlobal(float localX, float localY) {
      final int[] loc = new int[2];
      getLocationOnScreen(loc);
      final FlutterView flutterView = tryFindFlutterView();
      if (flutterView != null) {
        final int[] flutterLoc = new int[2];
        flutterView.getLocationOnScreen(flutterLoc);
        final float density = getResources().getDisplayMetrics().density;
        return new float[] {
          (loc[0] - flutterLoc[0] + localX) / density,
          (loc[1] - flutterLoc[1] + localY) / density
        };
      }
      final float density = getResources().getDisplayMetrics().density;
      return new float[] {(loc[0] + localX) / density, (loc[1] + localY) / density};
    }

    private void reportScrollGesture(
        ScrollGesturePhase phase,
        double timestamp,
        double globalX,
        double globalY,
        double localX,
        double localY,
        double deltaX,
        double deltaY,
        double velocityX,
        double velocityY) {
      final float density = getResources().getDisplayMetrics().density;
      api.getPigeonRegistrar()
          .runOnMainThread(
              () ->
                  api.onScrollGesture(
                      this,
                      phase,
                      timestamp,
                      globalX,
                      globalY,
                      localX / density,
                      localY / density,
                      deltaX / density,
                      deltaY / density,
                      velocityX / density,
                      velocityY / density,
                      reply -> null));
    }

    @Nullable
    @Override
    public View getView() {
      return this;
    }

    @Override
    public void dispose() {}

    // TODO(bparrishMines): This should be removed once https://github.com/flutter/engine/pull/40771
    // makes it to stable.
    // Temporary fix for https://github.com/flutter/flutter/issues/92165. The FlutterView is setting
    // setImportantForAutofill(IMPORTANT_FOR_AUTOFILL_YES_EXCLUDE_DESCENDANTS) which prevents this
    // view from automatically being traversed for autofill.
    @Override
    protected void onAttachedToWindow() {
      super.onAttachedToWindow();
      if (api.getPigeonRegistrar().sdkIsAtLeast(Build.VERSION_CODES.O)) {
        final FlutterView flutterView = tryFindFlutterView();
        if (flutterView != null) {
          flutterView.setImportantForAutofill(IMPORTANT_FOR_AUTOFILL_YES);
        }
      }
    }

    // Attempt to traverse the parents of this view until a FlutterView is found.
    private FlutterView tryFindFlutterView() {
      ViewParent currentView = this;

      while (currentView.getParent() != null) {
        currentView = currentView.getParent();
        if (currentView instanceof FlutterView) {
          return (FlutterView) currentView;
        }
      }

      return null;
    }

    @Override
    public void setWebViewClient(@NonNull WebViewClient webViewClient) {
      super.setWebViewClient(webViewClient);
      currentWebViewClient = webViewClient;
      currentWebChromeClient.setWebViewClient(webViewClient);
    }

    @Override
    public void setWebChromeClient(@Nullable WebChromeClient client) {
      super.setWebChromeClient(client);
      if (!(client instanceof WebChromeClientProxyApi.SecureWebChromeClient)) {
        throw new AssertionError("Client must be a SecureWebChromeClient.");
      }
      currentWebChromeClient = (WebChromeClientProxyApi.SecureWebChromeClient) client;
      currentWebChromeClient.setWebViewClient(currentWebViewClient);
    }

    // When running unit tests, the parent `WebView` class is replaced by a stub that returns null
    // for every method. This is overridden so that this returns the current WebChromeClient during
    // unit tests. This should only remain overridden as long as `setWebChromeClient` is overridden.
    @Nullable
    @Override
    public WebChromeClient getWebChromeClient() {
      return currentWebChromeClient;
    }

    @Override
    protected void onScrollChanged(int left, int top, int oldLeft, int oldTop) {
      super.onScrollChanged(left, top, oldLeft, oldTop);
      api.getPigeonRegistrar()
          .runOnMainThread(
              () ->
                  api.onScrollChanged(
                      this, (long) left, (long) top, (long) oldLeft, (long) oldTop, reply -> null));
    }
  }

  public WebViewProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public WebView pigeon_defaultConstructor() {
    DisplayListenerProxy displayListenerProxy = new DisplayListenerProxy();
    DisplayManager displayManager =
        (DisplayManager)
            getPigeonRegistrar().getContext().getSystemService(Context.DISPLAY_SERVICE);
    displayListenerProxy.onPreWebViewInitialization(displayManager);

    final WebView webView = new WebViewPlatformView(this);
    displayListenerProxy.onPostWebViewInitialization(displayManager);

    return webView;
  }

  @Override
  public void setScrollGestureListening(
      @NonNull WebView pigeon_instance, boolean enabled, boolean consume) {
    if (pigeon_instance instanceof WebViewPlatformView) {
      ((WebViewPlatformView) pigeon_instance).setScrollGestureListening(enabled, consume);
    }
  }

  @NonNull
  @Override
  public WebSettings settings(@NonNull WebView pigeon_instance) {
    return pigeon_instance.getSettings();
  }

  @Override
  public void loadData(
      @NonNull WebView pigeon_instance,
      @NonNull String data,
      @Nullable String mimeType,
      @Nullable String encoding) {
    pigeon_instance.loadData(data, mimeType, encoding);
  }

  @Override
  public void loadDataWithBaseUrl(
      @NonNull WebView pigeon_instance,
      @Nullable String baseUrl,
      @NonNull String data,
      @Nullable String mimeType,
      @Nullable String encoding,
      @Nullable String historyUrl) {
    pigeon_instance.loadDataWithBaseURL(baseUrl, data, mimeType, encoding, historyUrl);
  }

  @Override
  public void loadUrl(
      @NonNull WebView pigeon_instance, @NonNull String url, @NonNull Map<String, String> headers) {
    pigeon_instance.loadUrl(url, headers);
  }

  @Override
  public void postUrl(@NonNull WebView pigeon_instance, @NonNull String url, @NonNull byte[] data) {
    pigeon_instance.postUrl(url, data);
  }

  @Nullable
  @Override
  public String getUrl(@NonNull WebView pigeon_instance) {
    return pigeon_instance.getUrl();
  }

  @Override
  public boolean canGoBack(@NonNull WebView pigeon_instance) {
    return pigeon_instance.canGoBack();
  }

  @Override
  public boolean canGoForward(@NonNull WebView pigeon_instance) {
    return pigeon_instance.canGoForward();
  }

  @Override
  public void goBack(@NonNull WebView pigeon_instance) {
    pigeon_instance.goBack();
  }

  @Override
  public void goForward(@NonNull WebView pigeon_instance) {
    pigeon_instance.goForward();
  }

  @Override
  public void reload(@NonNull WebView pigeon_instance) {
    pigeon_instance.reload();
  }

  @Override
  public void clearCache(@NonNull WebView pigeon_instance, boolean includeDiskFiles) {
    pigeon_instance.clearCache(includeDiskFiles);
  }

  @Override
  public void evaluateJavascript(
      @NonNull WebView pigeon_instance,
      @NonNull String javascriptString,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    pigeon_instance.evaluateJavascript(
        javascriptString, result -> ResultCompat.success(result, callback));
  }

  @Nullable
  @Override
  public String getTitle(@NonNull WebView pigeon_instance) {
    return pigeon_instance.getTitle();
  }

  @Override
  public void setWebContentsDebuggingEnabled(boolean enabled) {
    WebView.setWebContentsDebuggingEnabled(enabled);
  }

  @Override
  public void setWebViewClient(@NonNull WebView pigeon_instance, @Nullable WebViewClient client) {
    pigeon_instance.setWebViewClient(client);
  }

  @SuppressLint("JavascriptInterface")
  @Override
  public void addJavaScriptChannel(
      @NonNull WebView pigeon_instance, @NonNull JavaScriptChannel channel) {
    pigeon_instance.addJavascriptInterface(channel, channel.javaScriptChannelName);
  }

  @Override
  public void removeJavaScriptChannel(@NonNull WebView pigeon_instance, @NonNull String channel) {
    pigeon_instance.removeJavascriptInterface(channel);
  }

  @Override
  public void setDownloadListener(
      @NonNull WebView pigeon_instance, @Nullable DownloadListener listener) {
    pigeon_instance.setDownloadListener(listener);
  }

  @Override
  public void setWebChromeClient(
      @NonNull WebView pigeon_instance,
      @Nullable WebChromeClientProxyApi.WebChromeClientImpl client) {
    pigeon_instance.setWebChromeClient(client);
  }

  @Override
  public void setBackgroundColor(@NonNull WebView pigeon_instance, long color) {
    pigeon_instance.setBackgroundColor((int) color);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  @Override
  public void destroy(@NonNull WebView pigeon_instance) {
    pigeon_instance.destroy();
  }
}
