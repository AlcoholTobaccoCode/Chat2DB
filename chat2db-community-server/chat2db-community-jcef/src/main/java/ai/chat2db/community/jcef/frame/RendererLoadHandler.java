package ai.chat2db.community.jcef.frame;

import ai.chat2db.community.jcef.enums.OSTypeEnum;
import ai.chat2db.community.jcef.renderer.RendererSource;
import org.cef.browser.CefBrowser;
import org.cef.browser.CefFrame;
import org.cef.handler.CefLoadHandler;
import org.cef.handler.CefLoadHandlerAdapter;
import org.cef.network.CefRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Objects;
import java.util.function.Supplier;

final class RendererLoadHandler extends CefLoadHandlerAdapter {

    private static final Logger log = LoggerFactory.getLogger(RendererLoadHandler.class);

    private final RendererSource rendererSource;
    private final Supplier<String> languagePreference;
    private final OSTypeEnum osType;

    RendererLoadHandler(RendererSource rendererSource, Supplier<String> languagePreference, OSTypeEnum osType) {
        this.rendererSource = Objects.requireNonNull(rendererSource, "rendererSource");
        this.languagePreference = Objects.requireNonNull(languagePreference, "languagePreference");
        this.osType = Objects.requireNonNull(osType, "osType");
    }

    @Override
    public void onLoadStart(CefBrowser browser, CefFrame frame, CefRequest.TransitionType transitionType) {
        if (frame == null || !frame.isMain()) {
            return;
        }
        browser.executeJavaScript(
                String.format("window.navigator.app_language = '%s';", languagePreference.get()),
                browser.getURL(),
                0
        );
        browser.executeJavaScript(
                String.format("window.navigator.os_type = '%s';", osType),
                browser.getURL(),
                0
        );
    }

    @Override
    public void onLoadError(CefBrowser browser, CefFrame frame, CefLoadHandler.ErrorCode errorCode,
                            String errorText, String failedUrl) {
        if (frame != null
                && frame.isMain()
                && rendererSource.developmentServer()
                && errorCode != CefLoadHandler.ErrorCode.ERR_ABORTED
                && rendererSource.isEntryRequest(failedUrl)) {
            log.warn("Development renderer failed to load: {}", failedUrl);
            browser.loadURL(rendererSource.loadFailurePageUrl());
        }
    }
}
