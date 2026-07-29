package ai.chat2db.community.jcef.renderer;

import ai.chat2db.community.tools.exception.BusinessException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RendererSourceResolverTest {

    @TempDir
    Path tempDir;

    @Test
    void resolvesDefaultDevelopmentServerForDevelopmentDesktop() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);

        assertEquals("http://127.0.0.1:8889/", source.entryUrl());
        assertTrue(source.developmentServer());
    }

    @Test
    void releaseUsesPackagedIndex() throws IOException {
        Path index = createPackagedIndex();

        RendererSource source = RendererSourceResolver.resolve(tempDir, true, true);

        assertEquals(index.toAbsolutePath().normalize().toUri().toString(), source.entryUrl());
        assertFalse(source.developmentServer());
    }

    @Test
    void nonDevelopmentDesktopUsesPackagedIndex() throws IOException {
        Path index = createPackagedIndex();

        RendererSource source = RendererSourceResolver.resolve(tempDir, false, false);

        assertEquals(index.toAbsolutePath().normalize().toUri().toString(), source.entryUrl());
        assertFalse(source.developmentServer());
    }

    @Test
    void missingPackagedIndexFailsWithExistingBusinessError() {
        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> RendererSourceResolver.resolve(tempDir, false, false)
        );

        assertEquals("Failed to load frontend files", exception.getMessage());
    }

    @Test
    void developmentSourceTrustsOnlyMainFramesFromItsExactOrigin() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);

        assertTrue(source.trusts(true, "http://127.0.0.1:8889/#/query?id=1"));
        assertTrue(source.trusts(true, "HTTP://127.0.0.1:8889/another/spa/path#settings"));
        assertFalse(source.trusts(false, "http://127.0.0.1:8889/"));
        assertFalse(source.trusts(true, "http://localhost:8889/"));
        assertFalse(source.trusts(true, "http://127.0.0.1:8888/"));
        assertFalse(source.trusts(true, "https://127.0.0.1:8889/"));
        assertFalse(source.trusts(true, "data:text/html,untrusted"));
        assertFalse(source.trusts(true, null));
    }

    @Test
    void packagedSourceTrustsOnlyItsNormalizedMainFrameFile() throws IOException {
        Path index = createPackagedIndex();
        Path sibling = Files.writeString(index.getParent().resolve("other.html"), "other");
        RendererSource source = RendererSourceResolver.resolve(tempDir, false, false);

        assertTrue(source.trusts(true, source.entryUrl()));
        assertTrue(source.trusts(true, source.entryUrl() + "#/query"));
        assertTrue(source.trusts(true, index.getParent().resolve(".").resolve("index.html").toUri() + "#settings"));
        assertFalse(source.trusts(false, source.entryUrl()));
        assertFalse(source.trusts(true, sibling.toUri().toString()));
        assertFalse(source.trusts(true, source.entryUrl() + "?unexpected=true"));
        assertFalse(source.trusts(true, "data:text/html,untrusted"));
    }

    @Test
    void packagedSourcePreservesEscapedCharactersWhenMatchingItsFile() throws IOException {
        Path appRoot = tempDir.resolve("Chat2DB Community");
        Path index = appRoot.resolve("dist/index.html");
        Files.createDirectories(index.getParent());
        Files.writeString(index, "<!doctype html>");
        RendererSource source = RendererSourceResolver.resolve(appRoot, false, true);

        assertTrue(source.entryUrl().contains("Chat2DB%20Community"));
        assertTrue(source.trusts(true, source.entryUrl() + "#boot"));
        assertTrue(source.isEntryRequest(source.entryUrl() + "#boot"));
    }

    @Test
    void developmentEntryMatchingIgnoresFragmentAndNormalizesTrailingSlash() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);

        assertTrue(source.isEntryRequest("http://127.0.0.1:8889/"));
        assertTrue(source.isEntryRequest("http://127.0.0.1:8889"));
        assertTrue(source.isEntryRequest("http://127.0.0.1:8889/#boot"));
        assertFalse(source.isEntryRequest("http://127.0.0.1:8889/dashboard"));
        assertFalse(source.isEntryRequest("http://127.0.0.1:8889//"));
        assertFalse(source.isEntryRequest("http://127.0.0.1:8889/../"));
        assertFalse(source.isEntryRequest("http://127.0.0.1:8889/?mode=desktop"));
        assertFalse(source.isEntryRequest("http://127.0.0.1:8888/"));
    }

    @Test
    void packagedEntryMatchingIgnoresOnlyFragment() throws IOException {
        Path index = createPackagedIndex();
        RendererSource source = RendererSourceResolver.resolve(tempDir, false, false);

        assertTrue(source.isEntryRequest(source.entryUrl()));
        assertTrue(source.isEntryRequest(source.entryUrl() + "#boot"));
        assertTrue(source.isEntryRequest(index.getParent().resolve(".").resolve("index.html").toUri().toString()));
        assertFalse(source.isEntryRequest(source.entryUrl() + "?mode=desktop"));
        assertFalse(source.isEntryRequest(index.getParent().resolve("other.html").toUri().toString()));
    }

    @Test
    void failurePageNamesFailedUrlCommandAndRetryTargetWithoutBecomingTrusted() {
        RendererSource source = RendererSourceResolver.resolve(tempDir, true, false);

        String failurePageUrl = source.loadFailurePageUrl();
        String prefix = "data:text/html;charset=UTF-8;base64,";

        assertTrue(failurePageUrl.startsWith(prefix));
        assertDoesNotThrow(() -> URI.create(failurePageUrl));
        String html = new String(
                Base64.getDecoder().decode(failurePageUrl.substring(prefix.length())),
                StandardCharsets.UTF_8
        );
        assertTrue(html.contains(source.entryUrl()));
        assertTrue(html.contains("yarn run start:community:hot"));
        assertTrue(html.contains("href=\"" + source.entryUrl() + "\""));
        assertFalse(source.trusts(true, failurePageUrl));
        assertFalse(source.isEntryRequest(failurePageUrl));
    }

    private Path createPackagedIndex() throws IOException {
        Path index = tempDir.resolve("dist/index.html");
        Files.createDirectories(index.getParent());
        return Files.writeString(index, "<!doctype html>");
    }
}
