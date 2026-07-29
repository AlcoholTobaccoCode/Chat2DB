package ai.chat2db.community.jcef.renderer;

import ai.chat2db.community.tools.exception.BusinessException;

import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Objects;

public final class RendererSourceResolver {

    private static final URI DEVELOPMENT_RENDERER_URI = URI.create("http://127.0.0.1:8889/");
    private static final String FRONTEND_LOAD_ERROR = "Failed to load frontend files";

    private RendererSourceResolver() {
    }

    public static RendererSource resolve(
            Path appRoot,
            boolean developmentDesktop,
            boolean release
    ) {
        if (developmentDesktop && !release) {
            return RendererSource.developmentServer(DEVELOPMENT_RENDERER_URI);
        }
        return resolvePackagedFile(appRoot);
    }

    private static RendererSource resolvePackagedFile(Path appRoot) {
        Path index = Objects.requireNonNull(appRoot, "appRoot")
                .resolve("dist")
                .resolve("index.html")
                .toAbsolutePath()
                .normalize();
        if (!Files.isRegularFile(index)) {
            throw new BusinessException(FRONTEND_LOAD_ERROR);
        }
        return RendererSource.packagedFile(index);
    }
}
