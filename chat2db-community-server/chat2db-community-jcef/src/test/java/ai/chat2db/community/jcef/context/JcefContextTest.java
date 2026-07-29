package ai.chat2db.community.jcef.context;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;

class JcefContextTest {

    @Test
    void exposesOsTypeBeforeBrowserContextIsBuilt() {
        assertNotNull(JcefContext.getInstance().getOsType());
    }
}
