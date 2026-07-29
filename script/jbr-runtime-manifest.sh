#!/usr/bin/env bash

# JetBrains Runtime release used by both local Desktop development and native
# packaging. Checksums come from JetBrains' official .checksum sidecars.
JBR_RUNTIME_RELEASE="17.0.12-b1207.37"
JBR_RUNTIME_DEFAULT_BASE_URL="https://cache-redirector.jetbrains.com/intellij-jbr"

resolve_jbr_runtime_artifact() {
    local platform="$1"
    local architecture="$2"

    JBR_RUNTIME_ARCHIVE=""
    JBR_RUNTIME_SHA512=""
    JBR_RUNTIME_PLATFORM_KEY=""

    case "${platform}:${architecture}" in
        Darwin:arm64|Darwin:aarch64)
            JBR_RUNTIME_ARCHIVE="jbr_jcef-17.0.12-osx-aarch64-b1207.37.tar.gz"
            JBR_RUNTIME_SHA512="de2a297b8acec5d594c13188510d5d29d11cb7e77c1a1eab7f0a566997c0aa1da308a1684f2afc20ac0ab410ac64bd4ce0e8dc92a601615d7b344d59d42c38e0"
            JBR_RUNTIME_PLATFORM_KEY="macos-aarch64"
            ;;
        Darwin:x86_64|Darwin:amd64)
            JBR_RUNTIME_ARCHIVE="jbr_jcef-17.0.12-osx-x64-b1207.37.tar.gz"
            JBR_RUNTIME_SHA512="b6862741fd4ea1f790d65d66cdd415097978f21f6f1f9b4d2aa5774b2b50408fcad38a8445efe7c405d86825d23dead4325a7ea0fd2298af5a19b4208236952c"
            JBR_RUNTIME_PLATFORM_KEY="macos-x64"
            ;;
        Linux:arm64|Linux:aarch64)
            JBR_RUNTIME_ARCHIVE="jbr_jcef-17.0.12-linux-aarch64-b1207.37.tar.gz"
            JBR_RUNTIME_SHA512="cc150d66d338363f7d09248ba922b35e3adf4679004ea83e76883a5720860f2d895bd4c6e00f9162ac8880303cafd3cecb65f35a1e495114dfa7618a5e994091"
            JBR_RUNTIME_PLATFORM_KEY="linux-aarch64"
            ;;
        Linux:x86_64|Linux:amd64)
            JBR_RUNTIME_ARCHIVE="jbr_jcef-17.0.12-linux-x64-b1207.37.tar.gz"
            JBR_RUNTIME_SHA512="b08796c2d18ff8be6a038f2471ddbcbeaacb03fbac49dc3b6ac61d23db20e7d346834a3a407d4a670f2911b20d435aab74eb4cb1d64fab3ebc6e698a52387020"
            JBR_RUNTIME_PLATFORM_KEY="linux-x64"
            ;;
        Windows:x86_64|Windows:amd64|MINGW*:x86_64|MINGW*:amd64|MSYS*:x86_64|MSYS*:amd64|CYGWIN*:x86_64|CYGWIN*:amd64)
            JBR_RUNTIME_ARCHIVE="jbr_jcef-17.0.12-windows-x64-b1207.37.tar.gz"
            JBR_RUNTIME_SHA512="d0649ff8efab9bd1f682b044c6a5422714e9af75522d86c653ebcbf01c4aaf2595ca8873aa2e3f45207f57408d7d043f3fd1b1e501520d5788836c7ebe897f01"
            JBR_RUNTIME_PLATFORM_KEY="windows-x64"
            ;;
        *)
            return 1
            ;;
    esac
}
