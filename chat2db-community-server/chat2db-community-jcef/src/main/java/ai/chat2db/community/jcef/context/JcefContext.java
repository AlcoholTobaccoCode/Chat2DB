package ai.chat2db.community.jcef.context;

import ai.chat2db.community.jcef.enums.OSTypeEnum;
import ai.chat2db.community.jcef.frame.DevToolsPanel;
import ai.chat2db.community.jcef.frame.MainJFrame;
import ai.chat2db.community.jcef.utils.OSOperateUtil;
import com.jetbrains.cef.JCefAppConfig;
import lombok.Getter;
import org.cef.CefApp;
import org.cef.CefClient;
import org.cef.browser.CefBrowser;

import javax.swing.*;
import java.awt.*;
import java.util.Locale;
import java.util.Map;


@Getter
public final class JcefContext {

    private JSplitPane splitPane;
    private DevToolsPanel devToolsPanel;
    private CefApp cefApp_;
    private CefClient client_;
    private CefBrowser browser_;
    private Component browserUI_;
    private MainJFrame frame_;
    private JCefAppConfig jcefAppConfig_;
    private final OSTypeEnum osType = resolveOsType();
    private Integer screenWidth;
    private Integer screenHeight;

    private JcefContext() {

    }

    private static class JcefContextHolder {
        private static final JcefContext INSTANCE = new JcefContext();
    }

    public void buildJcefContext(MainJFrame frame,
                                 CefBrowser browser,
                                 CefClient cefClient,
                                 CefApp cefApp,
                                 JSplitPane splitPane,
                                 DevToolsPanel devToolsPanel,
                                 Component browserUI,
                                 JCefAppConfig jCefAppConfig) {
        this.frame_ = frame;
        this.browser_ = browser;
        this.client_ = cefClient;
        this.cefApp_ = cefApp;
        this.splitPane = splitPane;
        this.devToolsPanel = devToolsPanel;
        this.browserUI_ = browserUI;
        this.jcefAppConfig_ = jCefAppConfig;

        Map<String, Integer> screenInfo = OSOperateUtil.getScreenInfo(frame_);
        screenWidth = screenInfo.get("width");
        screenHeight = screenInfo.get("height");
    }

    public static JcefContext getInstance() {
        return JcefContextHolder.INSTANCE;
    }

    private static OSTypeEnum resolveOsType() {
        String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        if (os.startsWith("windows")) {
            return OSTypeEnum.Windows;
        }
        if (os.startsWith("linux")) {
            return OSTypeEnum.Linux;
        }
        if (os.startsWith("mac")) {
            return OSTypeEnum.Mac;
        }
        return OSTypeEnum.Other;
    }
}
