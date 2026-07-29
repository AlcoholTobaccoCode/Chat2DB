package ai.chat2db.community.jcef.renderer;

import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Base64;
import java.util.Locale;
import java.util.Objects;

public final class RendererSource {

    private final URI entryUri;
    private final String entryUrl;
    private final boolean developmentServer;
    private final Path packagedIndex;
    private final Origin developmentOrigin;

    private RendererSource(URI entryUri, boolean developmentServer, Path packagedIndex) {
        this.entryUri = URI.create(Objects.requireNonNull(entryUri, "entryUri").toASCIIString());
        this.entryUrl = this.entryUri.toASCIIString();
        this.developmentServer = developmentServer;
        this.packagedIndex = packagedIndex;
        this.developmentOrigin = developmentServer ? Origin.from(this.entryUri) : null;
    }

    static RendererSource developmentServer(URI entryUri) {
        return new RendererSource(entryUri, true, null);
    }

    static RendererSource packagedFile(Path packagedIndex) {
        Path normalizedIndex = Objects.requireNonNull(packagedIndex, "packagedIndex")
                .toAbsolutePath()
                .normalize();
        return new RendererSource(normalizedIndex.toUri(), false, normalizedIndex);
    }

    public String entryUrl() {
        return entryUrl;
    }

    public boolean developmentServer() {
        return developmentServer;
    }

    public boolean trusts(boolean mainFrame, String frameUrl) {
        if (!mainFrame) {
            return false;
        }
        URI frameUri = parse(frameUrl);
        if (frameUri == null) {
            return false;
        }
        if (developmentServer) {
            return frameUri.getRawUserInfo() == null
                    && developmentOrigin.equals(Origin.from(frameUri));
        }
        return matchesPackagedFile(frameUri);
    }

    public boolean isEntryRequest(String url) {
        URI requestUri = parse(url);
        if (requestUri == null || requestUri.getRawQuery() != null || requestUri.getRawUserInfo() != null) {
            return false;
        }
        if (!developmentServer) {
            return matchesPackagedFile(requestUri);
        }
        if (!developmentOrigin.equals(Origin.from(requestUri))) {
            return false;
        }
        return normalizeEntryPath(entryUri.getRawPath())
                .equals(normalizeEntryPath(requestUri.getRawPath()));
    }

    public String loadFailurePageUrl() {
        String escapedEntryUrl = escapeHtml(entryUrl);
        String html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Chat2DB renderer unavailable</title>"
                + "<style>body{font-family:sans-serif;margin:48px;color:#202124}code{display:block;margin:16px 0;"
                + "padding:12px;background:#f1f3f4}a{color:#0969da}</style></head><body>"
                + "<h1>Development renderer unavailable</h1><p>Failed to load " + escapedEntryUrl + ".</p>"
                + "<p>Start it from the frontend directory:</p><code>yarn run start:community:hot</code>"
                + "<a href=\"" + escapedEntryUrl + "\">Retry</a></body></html>";
        return "data:text/html;charset=UTF-8;base64,"
                + Base64.getEncoder().encodeToString(html.getBytes(StandardCharsets.UTF_8));
    }

    private boolean matchesPackagedFile(URI candidate) {
        if (!"file".equalsIgnoreCase(candidate.getScheme())
                || candidate.getRawQuery() != null
                || candidate.getRawUserInfo() != null) {
            return false;
        }
        try {
            String candidateUrl = candidate.toASCIIString();
            int fragmentStart = candidateUrl.indexOf('#');
            URI fileUri = URI.create(fragmentStart < 0 ? candidateUrl : candidateUrl.substring(0, fragmentStart));
            Path candidatePath = Path.of(fileUri).toAbsolutePath().normalize();
            return packagedIndex.equals(candidatePath);
        } catch (IllegalArgumentException exception) {
            return false;
        }
    }

    private static URI parse(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return new URI(value);
        } catch (URISyntaxException exception) {
            return null;
        }
    }

    private static String normalizeEntryPath(String path) {
        if (path == null || path.isEmpty()) {
            return "/";
        }
        if (path.length() > 1 && path.endsWith("/") && path.charAt(path.length() - 2) != '/') {
            return path.substring(0, path.length() - 1);
        }
        return path;
    }

    private static String escapeHtml(String value) {
        return value
                .replace("&", "&amp;")
                .replace("\"", "&quot;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }

    private record Origin(String scheme, String host, int port) {

        private static Origin from(URI uri) {
            String scheme = uri.getScheme();
            String host = uri.getHost();
            if (scheme == null || host == null) {
                return null;
            }
            int port = uri.getPort() < 0 ? defaultPort(scheme) : uri.getPort();
            if (port < 0) {
                return null;
            }
            return new Origin(
                    scheme.toLowerCase(Locale.ROOT),
                    normalizeHost(host),
                    port
            );
        }

        private static int defaultPort(String scheme) {
            if ("http".equalsIgnoreCase(scheme)) {
                return 80;
            }
            if ("https".equalsIgnoreCase(scheme)) {
                return 443;
            }
            return -1;
        }

        private static String normalizeHost(String host) {
            String normalized = host.toLowerCase(Locale.ROOT);
            if (normalized.startsWith("[") && normalized.endsWith("]")) {
                return normalized.substring(1, normalized.length() - 1);
            }
            return normalized;
        }
    }
}
