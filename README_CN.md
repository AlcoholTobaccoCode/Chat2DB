<div align="center">
  <img src="./icon.png" alt="Chat2DB" width="100">
  <div align="center">
  Powered by  <a href="https://ottermind.ai">OtterMind</a>
</div>
  <br/>
  <p><strong>面向开发者、DBA、分析师和数据团队的 AI 驱动数据库客户端与 SQL 工作空间。</strong></p>
</div>

<div align="center">
  <a href="./README.md"><img alt="README in English" src="https://img.shields.io/badge/English-d9d9d9"></a>
  <a href="./README_CN.md"><img alt="简体中文版自述文件" src="https://img.shields.io/badge/简体中文-d9d9d9"></a>
  <a href="./README_JA.md"><img alt="日本語のREADME" src="https://img.shields.io/badge/日本語-d9d9d9"></a>
  <a href="./README_ES.md"><img alt="README en español" src="https://img.shields.io/badge/Español-d9d9d9"></a>
  <a href="./README_KO.md"><img alt="한국어 README" src="https://img.shields.io/badge/한국어-d9d9d9"></a>
</div>

## Chat2DB 是什么?

Chat2DB Community 是一款免费的跨平台数据库客户端,支持 Windows、macOS 和 Linux。它完全运行在你自己的机器上,提供功能完整的 SQL 工作空间,并可接入你自己的 AI 模型作为智能助手。

- **30+ 种数据库** —— MySQL、PostgreSQL、Oracle、SQL Server、ClickHouse、MongoDB、Redis、SQLite、MariaDB、TiDB、Hive、DB2、Snowflake、BigQuery、Elasticsearch 等,通过插件扩展。
- **SQL 工作空间** —— SQL 编辑、补全、格式化、执行、SQL 收藏与历史记录。
- **AI 助手** —— 接入自定义 AI 模型,用自然语言生成、解释和优化 SQL。
- **数据库管理** —— 元数据浏览、表和对象管理(DDL/DML)、在线编辑数据。
- **数据导入导出**、**Dashboard 与图表**,以及支持 **[MCP 的开源 CLI](https://github.com/OtterMind/Chat2DB-CLI)**。

<div align="center">

[![Chat2DB 工作台:SQL 编辑器与 AI 助手 —— 点击观看介绍视频](https://cdn.chat2db-ai.com/website/img/first_video_cover.webp)](https://cdn.chat2db-ai.com/website/video/first_sceen_en.mp4)

</div>

### 产品界面

| Dashboard 与图表 | ER 图 |
| --- | --- |
| ![Dashboard 与图表](https://cdn.chat2db-ai.com/website/img/bi_dashboard.png) | ![ER 图](https://cdn.chat2db-ai.com/website/img/er_diagrams.png) |

| 可视化数据管理 | 数据导入导出 |
| --- | --- |
| ![可视化数据管理](https://cdn.chat2db-ai.com/website/img/visual_data_mnagement_en.png) | ![数据导入导出](https://cdn.chat2db-ai.com/website/img/import_export_data_en.png) |

## 快速开始

### 方式一:桌面应用

从 [GitHub Releases](https://github.com/OtterMind/Chat2DB/releases) 下载对应平台的安装包,安装后即可连接数据库使用,无需其他配置。

### 方式二:Docker

系统要求:Docker 19.03.0+、Docker Compose 2.0.0+(Compose V2,仅 Compose 方式需要)、CPU 2 核以上、内存 4 GiB 以上。

先创建加密密钥(用途见[加密密钥](#加密密钥)一节),再启动容器:

```bash
# 在仓库目录中首次执行一次;重复执行会复用同一把合法密钥。
git clone https://github.com/OtterMind/Chat2DB.git && cd Chat2DB
./script/security/init-community-encryption-key.sh

docker run --detach \
  --name chat2db-community \
  --restart unless-stopped \
  --publish 127.0.0.1:10825:10825 \
  --volume "$HOME/.chat2db-community-docker:/root/.chat2db-community" \
  --env CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE=/run/secrets/chat2db-community-encryption.key \
  --volume "$HOME/.config/chat2db-community/encryption.key:/run/secrets/chat2db-community-encryption.key:ro" \
  chat2db/chat2db:latest
```

然后在浏览器中访问 `http://localhost:10825`。

也可以使用仓库自带的 Compose 配置:

```bash
./script/security/init-community-encryption-key.sh
docker compose --file docker/docker-compose.yml up --detach
```

注意事项:

- 更新时先拉取新镜像、删除旧容器,再重新执行启动命令。容器重建时必须保留 `~/.config/chat2db-community/encryption.key`。
- `docker run` 示例将应用数据保存在 `$HOME/.chat2db-community-docker`;Compose 配置使用名为 `chat2db-community-data` 的命名卷。两处存储不会自动共享数据。
- Chat2DB Community 5.3.0 使用独立的 `/root/.chat2db-community` 目录,不会自动迁移旧镜像 `/root/.chat2db` 中的数据。

## 安全须知

Chat2DB Community 是单用户、本机优先的应用,不提供用户账号或多用户之间的
权限边界。HTTP 服务必须绑定到 `127.0.0.1` 或 `::1`,不要暴露给其他用户或
不可信网络。

自定义 JDBC Driver 是可执行 Java 代码,只应安装来自可信来源的驱动。导入的
配置文件、压缩包、SQL 文件、数据库内容和 AI 响应仍属于不可信数据。完整信任
边界和漏洞报告流程请参阅[安全策略](SECURITY.md)。

如果你觉得这个项目对你有用,帮我们点个 Star ⭐️ 吧!

<div align="center">
  <a href="https://github.com/OtterMind/Chat2DB"><img src="https://cdn.chat2db.ai/g/Area.gif" alt="给 Chat2DB 点个 Star" width="600"></a>
</div>

## 加密密钥

Chat2DB Community 使用 AES-256-GCM 加密保存的数据源密码和 AI 模型 API Key,每个安装实例使用独立密钥。在仓库目录中执行一次以下命令创建密钥(依赖 `openssl`):

```bash
./script/security/init-community-encryption-key.sh
```

密钥会写入 `~/.config/chat2db-community/encryption.key`。**请单独备份该文件,并在升级和容器重建时保留** —— 替换或丢失密钥会导致已保存的数据源密码和 AI 模型 API Key 无法解密。Web/headless 方式启动时缺少合法密钥会直接启动失败;只有 Desktop 模式会自动创建缺失的密钥。

<details>
<summary>密钥配置参考(自定义路径、解析优先级、校验规则)</summary>

密钥必须是合法的 Base64,且解码后恰好为 32 字节。仓库提供的初始化脚本会生成标准带填充格式,即 44 个 Base64 字符并以 `=` 结尾。它是加密密钥材料,不是用户自行输入的普通口令。数据源密码和 AI API Key 使用同一把密钥,但使用不同的认证 AAD,因此一种用途的密文不能作为另一种用途解密。

如需使用自定义路径,应在初始化脚本和 Chat2DB 启动参数中指定同一路径:

```bash
./script/security/init-community-encryption-key.sh /secure/path/chat2db-community.key

java -Dloader.path=chat2db-community-server/chat2db-community-start/target/lib \
    -Dchat2db.runtime.mode=community \
    -Dchat2db.mode=WEB \
    -Dchat2db.gui=false \
    -Dchat2db.network.status=OFFLINE \
    -Dchat2db.community.encryption-key-file=/secure/path/chat2db-community.key \
    -Dserver.address=127.0.0.1 \
    -Dserver.port=10825 \
    -jar chat2db-community-server/chat2db-community-start/target/chat2db-community.jar
```

脚本选择密钥文件路径的优先级依次为位置参数、`CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE` 和默认路径。脚本会复用已有的合法普通文件,拒绝符号链接和非普通文件;如果已有文件不合法,脚本会报错且不会覆盖。密钥文件应当只允许 Chat2DB 进程所属用户读取。

密钥配置按以下优先级解析:

1. JVM 参数 `chat2db.community.encryption-key`,值为 Base64 密钥。
2. 环境变量 `CHAT2DB_COMMUNITY_ENCRYPTION_KEY`,值为 Base64 密钥。
3. JVM 参数 `chat2db.community.encryption-key-file`,值为密钥文件路径。
4. 环境变量 `CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE`,值为密钥文件路径。
5. 默认文件 `~/.config/chat2db-community/encryption.key`。

第一个已配置的值具有最高优先级。空值、非法 Base64、解码后不是 32 字节的密钥或非法密钥文件都会直接导致启动失败,不会静默回退到下一项。推荐使用密钥文件,避免把密钥值直接暴露在进程参数或环境变量中。

密钥文件是否自动创建只取决于 `chat2db.mode`,与 `chat2db.gui` 无关。Community Desktop 模式(`chat2db.runtime.mode=community` 且 `chat2db.mode=DESKTOP`)会在未配置内联密钥且所选密钥文件不存在时自动创建该文件。任何非 Desktop 模式(包括常规 Web/headless 启动)都不会创建缺失的密钥,必须提前初始化或显式配置合法密钥,否则启动失败。解析后的密钥会在进程生命周期内缓存,因此修改密钥配置后必须重启应用。

</details>

## 从源码构建

### 环境要求

- Java 17 JDK:<a href="https://adoptium.net/temurin/releases/?version=17" target="_blank">Eclipse Temurin 17</a>
- Node.js >=18.17 且 <19、20.x 或 22.x(推荐 22.22.2)
- Yarn 1.22.22,并使用仓库中已有的 lockfile
- Maven 3.8 或以上版本
- Bash 3.2 或以上版本、`curl`、`tar`,以及 `sha512sum`、`shasum`、`openssl` 中至少一个 SHA-512 校验工具(Windows 请使用 Git Bash)

### 克隆仓库

```bash
git clone https://github.com/OtterMind/Chat2DB.git
cd Chat2DB
```

### 一键启动开发环境

在仓库根目录执行启动脚本:

| 目标 | 命令 |
| --- | --- |
| 启动 Web 后端和前端开发服务器 | `./script/dev-community.sh` 或 `./script/dev-community.sh web` |
| 启动 JCEF Desktop 和前端开发服务器 | `./script/dev-community.sh desktop` |
| 启动前强制重建后端 | 追加 `--build` |
| 只查看解析后的命令,不启动进程 | 追加 `--dry-run` |

启动前必须确保 `127.0.0.1:8889` 和 `127.0.0.1:10825` 都未被占用。脚本不会停止
或复用无关进程,`--build` 也不会重启现有实例。从另一个 checkout 启动前,请先在
原启动终端按 `Ctrl+C` 停止脚本。

首次运行时,脚本会按需安装前端依赖、构建缺失或已过期的后端产物并初始化
Community 本地加密密钥。按 `Ctrl+C` 会同时停止本次启动的两个进程。需要强制
重建后端时使用 `./script/dev-community.sh --build`。

脚本会先检查显式 `JBR_HOME`、`JAVA_HOME`、当前 `PATH` 中 Java 报告的真实
`java.home`(兼容 jenv、asdf、mise 和 SDKMAN)、macOS 已安装的 Chat2DB
Community.app 以及仓库内已准备的运行时。如果都不包含 JCEF,脚本会按当前受支持
平台下载仓库锁定的 JetBrains Runtime,使用 JetBrains 官方 SHA-512 校验后写入
用户缓存。自动下载支持 macOS arm64/x64、Linux arm64/x64 和 Windows x64。首次
下载约 180-205 MiB,后续启动直接复用已校验缓存。因此新电脑 clone 项目后不需要
先安装 `/Applications/Chat2DB Community.app`,也不需要手工配置 `JBR_HOME`;jenv
当前的普通 Temurin 17 仍可继续用于日常 Java 开发。

`JBR_HOME` 仍可作为显式覆盖,但值无效时会立即失败。
`CHAT2DB_JBR_DOWNLOAD=never` 只禁止自动下载 JBR;此时必须已有可解析的兼容 JBR,
而 Maven 或 Yarn 仍可能联网。自定义绝对缓存路径可设置
`CHAT2DB_JBR_CACHE_DIR`,使用镜像可设置 `CHAT2DB_JBR_BASE_URL`(必须为 HTTPS,
且提供完全相同的锁定归档)。Windows Git Bash 可直接传入 `C:\...` 路径。
脚本会校验 Java 17、JCEF 模块、项目要求的 JCEF 版本和原生资源。执行
`./script/dev-community.sh desktop --dry-run` 只打印缓存、下载计划和进程命令,
不会联网或写缓存。Desktop 进程自身包含后端,不会再启动一个独立 Web 后端。

仓库用 `.node-version`、`.nvmrc`、`.tool-versions` 和 Volta 配置统一推荐的
Node.js 22.22.2。已激活的 Node.js >=18.17 且 <19、20.x、22.x 均受支持;Node.js 24
与当前 Umi 工具链不兼容。特殊安装布局可通过 `CHAT2DB_NODE_HOME` 显式指定。
脚本可以从本机已安装版本中选择兼容的 Node.js,但不会安装 Node.js、Yarn、Maven
或其他前置命令行工具。

#### 热更新边界

开发模式下,浏览器和 JCEF Desktop 都从 `http://127.0.0.1:8889/` 加载前端。
启动脚本所在 checkout 中的 React、TypeScript 和样式文件会被自动监听。Webpack
首次编译和较大的增量编译可能需要数秒;排查热更新前,先等待启动终端出现
`[Webpack] Compiled`,并确认浏览器控制台出现 `[webpack] connected.`。

编译成功不会绕过 React 路由、组件状态或条件渲染。如果临时添加的 UI 标记已经
进入 bundle 却没有显示,应先确认当前页面和状态确实会进入该代码分支。使用第二个
clone 模拟新电脑时,启动期间也必须编辑这个 clone;另一个主仓库不在它的监听范围内。

Java 后端和 JCEF 代码不会热加载到正在运行的 JVM。修改后先按 `Ctrl+C` 停止脚本,
再重新启动。脚本会自动重建比 JAR 更新的后端源码;需要确保完整重建时追加
`--build`。

#### 模拟全新电脑

全新 clone 不要求预装 Chat2DB Community,也不要求开发者手工下载 JBR。若要在
不删除 macOS 已安装 App、不动正常用户缓存的情况下验证自动下载路径,请使用独立
clone、独立空缓存目录和一个明确不存在的 App 路径:

```bash
CHAT2DB_TEST_JBR_CACHE="$(mktemp -d)"
CHAT2DB_COMMUNITY_APP="/nonexistent/Chat2DB Community.app" \
CHAT2DB_JBR_CACHE_DIR="${CHAT2DB_TEST_JBR_CACHE}" \
./script/dev-community.sh desktop
```

如果测试目标是验证自动下载,请不要设置 `JBR_HOME`,并让当前 Java 保持为普通
Java 17 JDK。验证完成后只需处理这个独立缓存目录;无需删除已安装 App、正常 JBR
缓存、主开发仓库或 Chat2DB 应用数据。该方法验证的是 clone 初始化、依赖准备、
JBR 下载和进程启动链路,不会模拟一个空的 Chat2DB 用户数据目录。

### 手工启动前端

请使用仓库中的 Yarn lockfile。

```bash
cd Chat2DB/chat2db-community-client
yarn install --frozen-lockfile
yarn run start:community:hot
```

Community 开发服务器仅监听 `127.0.0.1:8889`。当前 Umi 横幅仍可能列出
Network 地址,但启动保护会将真实 socket 限制在回环地址。如果 8889 已被占用,
启动会直接失败,不会静默改用其他端口。

### 手工启动后端

```bash
cd Chat2DB
mvn -B clean package -Dmaven.test.skip=true -Dchat2db.finalName=chat2db-community \
    -f chat2db-community-server/pom.xml \
    -pl chat2db-community-start -am
./script/security/init-community-encryption-key.sh
java -Dloader.path=chat2db-community-server/chat2db-community-start/target/lib \
    -Dchat2db.gui=false \
    -Dchat2db.runtime.mode=community \
    -Dchat2db.mode=WEB \
    -Dchat2db.network.status=OFFLINE \
    -Dchat2db.community.encryption-key-file="$HOME/.config/chat2db-community/encryption.key" \
    -Dserver.address=127.0.0.1 \
    -Dserver.port=10825 \
    -Dspring.profiles.active=dev \
    -jar chat2db-community-server/chat2db-community-start/target/chat2db-community.jar
```

浏览器开发需要让前端和后端命令作为两个独立进程同时运行,然后访问
`http://127.0.0.1:8889/`。

### 桌面端开发(JCEF)

桌面端开发请使用一键启动脚本。它会启动前端开发服务器、检查 Desktop 所需的
外置依赖,并同时兼容完整 JBR 解压目录和 macOS 已安装 App 的 JBR/JCEF 拆分
布局。此时不要再启动 Web 后端,Desktop 进程自身会占用
`127.0.0.1:10825`。

```bash
./script/dev-community.sh desktop
```

Desktop JVM 参数和 JCEF 布局会随平台变化,因此固定的手工 Java 命令不能等价替代
启动脚本。执行 `./script/dev-community.sh desktop --dry-run` 可查看当前机器的准确
命令。如果确实要手工执行该命令,请先运行 `yarn run start:community:hot`,并等待
`127.0.0.1:8889` 就绪。

在 `dev + DESKTOP` 模式下,JCEF 会自动加载 `http://127.0.0.1:8889/`。
release 运行时会继续加载包内的 `dist/index.html`。

### 构建本地 Docker 镜像

```bash
./docker/docker-build.sh 5.3.0 chat2db/chat2db:5.3.0
```

## 社区版与商业版

社区版包含上述完整的本地数据库客户端能力,包括自定义 AI 模型支持。商业版 Pro 和 Enterprise 在同一核心之上增加官方 AI 服务、账号体系、云端存储与多设备同步,以及团队协作和治理能力。详情请见 [chat2db.ai](https://chat2db.ai)。

## 参与贡献

我们欢迎社区提交 Bug、功能建议、文档改进、测试反馈和 Pull Request。

创建 Issue 或提交 Pull Request 前,请先阅读[贡献指南](./CONTRIBUTING.md)。其中说明了如何报告问题、提出建议,以及如何让维护者更高效地审查贡献。

- Bug 和功能建议请使用 [GitHub Issues](https://github.com/OtterMind/Chat2DB/issues)。
- 使用问题、配置帮助和开放讨论请使用 [GitHub Discussions](https://github.com/OtterMind/Chat2DB/discussions)。
- 如果 Pull Request 与某个 Issue 相关,请在 PR 描述中附上对应链接。

## 社区与支持

- GitHub Issues:[报告 Bug 或提出功能建议](https://github.com/OtterMind/Chat2DB/issues)
- GitHub Discussions:[提问与交流](https://github.com/OtterMind/Chat2DB/discussions)
- Discord:[加入我们的 Discord 服务器](https://discord.gg/uNjb3n5JVN)
- Email:Chat2DB@ch2db.com

## 致谢

感谢所有为 Chat2DB 贡献力量的同学们。

<a href="https://github.com/OtterMind/Chat2DB/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=OtterMind/Chat2DB" alt="Chat2DB 贡献者" />
</a>

## 许可证

Chat2DB Community 5.3.0 及后续版本适用本仓库的
[LICENSE](./LICENSE)。该许可基于 Apache License 2.0 并附加了使用条件,
属于 Source Available 许可。Chat2DB 5.3.0 之前发布的所有版本,包括 0.3.7
以及更早的历史版本,继续适用 Apache License 2.0。
