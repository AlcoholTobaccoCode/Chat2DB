package ai.chat2db.community.jcef.frame;

import ai.chat2db.community.jcef.enums.OSTypeEnum;
import ai.chat2db.community.jcef.renderer.RendererSource;
import ai.chat2db.community.jcef.renderer.RendererSourceResolver;
import org.cef.browser.CefBrowser;
import org.cef.browser.CefFrame;
import org.cef.handler.CefLoadHandler;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.lang.reflect.Proxy;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RendererLoadHandlerTest {

    @TempDir
    Path tempDir;

    @Test
    void injectsLanguageAndOsBeforeMainFrameLoads() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);
        List<String> scripts = new ArrayList<>();
        RendererLoadHandler handler = new RendererLoadHandler(source, () -> "zh-CN", OSTypeEnum.Mac);

        handler.onLoadStart(browser(scripts, new ArrayList<>()), frame(true), null);

        assertEquals(List.of(
                "window.navigator.app_language = 'zh-CN';",
                "window.navigator.os_type = 'Mac';"
        ), scripts);
    }

    @Test
    void redirectsFailedDevelopmentEntryToFailurePage() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);
        List<String> loadedUrls = new ArrayList<>();
        RendererLoadHandler handler = new RendererLoadHandler(source, () -> "en-US", OSTypeEnum.Linux);

        handler.onLoadError(
                browser(new ArrayList<>(), loadedUrls),
                frame(true),
                CefLoadHandler.ErrorCode.ERR_CONNECTION_REFUSED,
                "Connection refused",
                source.entryUrl()
        );

        assertEquals(List.of(source.loadFailurePageUrl()), loadedUrls);
    }

    @Test
    void ignoresSubframeAbortedAndNonEntryFailures() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);
        List<String> loadedUrls = new ArrayList<>();
        CefBrowser browser = browser(new ArrayList<>(), loadedUrls);
        RendererLoadHandler handler = new RendererLoadHandler(source, () -> "en-US", OSTypeEnum.Windows);

        handler.onLoadError(browser, frame(false), CefLoadHandler.ErrorCode.ERR_CONNECTION_REFUSED,
                "Connection refused", source.entryUrl());
        handler.onLoadError(browser, frame(true), CefLoadHandler.ErrorCode.ERR_ABORTED,
                "Aborted", source.entryUrl());
        handler.onLoadError(browser, frame(true), CefLoadHandler.ErrorCode.ERR_CONNECTION_REFUSED,
                "Connection refused", source.entryUrl() + "dashboard");

        assertTrue(loadedUrls.isEmpty());
    }

    private static CefBrowser browser(List<String> scripts, List<String> loadedUrls) {
        return proxy(CefBrowser.class, (method, args) -> {
            if ("executeJavaScript".equals(method)) {
                scripts.add((String)args[0]);
            } else if ("loadURL".equals(method)) {
                loadedUrls.add((String)args[0]);
            }
            return null;
        });
    }

    private static CefFrame frame(boolean main) {
        return proxy(CefFrame.class, (method, args) -> "isMain".equals(method) ? main : null);
    }

    private static <T> T proxy(Class<T> type, MethodHandler handler) {
        return type.cast(Proxy.newProxyInstance(
                type.getClassLoader(),
                new Class<?>[]{type},
                (proxy, method, args) -> handler.invoke(method.getName(), args)
        ));
    }

    @FunctionalInterface
    private interface MethodHandler {
        Object invoke(String method, Object[] args);
    }
}
