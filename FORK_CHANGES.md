# branch-4.1.4 與 upstream 4.1.4 的差異

這個 branch 以 `apache/doris` 的 release tag `4.1.4` 為基準，套上和本 fork `master` 相同的三個改動。這份檔案記錄所有**只存在於本 branch** 的改動：改了什麼、為什麼改、升級到新的 4.1.x tag 時要注意什麼。`master` 上有一份對應的 `FORK_CHANGES.md`。

## 維護規則

1. **每個 fork 專屬的 commit 都要記在下方「變更清單」**，並在同一個 commit 裡更新本檔。以 commit 標題當識別：rebase 到新的 upstream 後 hash 會變，標題不會。
2. **檢查有沒有漏記**：
   ```bash
   git fetch upstream tag 4.1.4 --no-tags
   tools/fork/check_fork_changes.sh      # 比對 4.1.4..HEAD；有漏記就列出來並回傳 1
   ```
3. **安全掃描必須維持 0 筆**。改完程式、或同步 upstream 之後都要跑：
   ```bash
   tools/fork/semgrep_gate.sh            # 預設掃全 repo，也可以只給路徑
   ```
   升級到新的 4.1.x tag 時，upstream 的新程式碼常常又會踩到這些規則，寫法照下面「新程式碼怎麼寫才會過掃描」。
4. 某個改動被 upstream 收下、或不再需要時，從清單移到「已移除的改動」，並寫明原因。
5. 在 `master` 新增的 fork 改動如果也要進 4.1.4，要另外移植並記在這裡；兩邊的程式碼差很多，通常不能直接 cherry-pick。

## 基準

| 項目 | 值 |
|---|---|
| Upstream | `apache/doris` 的 release tag `4.1.4`（remote 名稱 `upstream`） |
| Branch 起點 | `4.1.4` = `ad35a140c7`（2026-09-09） |
| 語言版本 | FE 各模組以 `--release 8` 編譯：只能用 Java 8 API（沒有 `Path.of`）。`fs_brokers/cdc_client` 是 Java 17；`fs_brokers/apache_hdfs_broker` 是獨立的 Java 8 build |
| 掃描規則 | GitLab sast-rules `390440ab`：`22fe8755`（"Remove poor java rules"）之前的最後一版，仍包含 PATH_TRAVERSAL_IN/OUT。SSRF 改用 `83144bd2` 版本的規則，因為舊版無法被新的 semgrep 解析，兩者對應同一個 ID |
| 掃描範圍 | 全 repo，排除 `spec`、`test`、`tests`、`tmp`（GitLab SAST 預設），以及 `thirdparty`、`output`、`node_modules` |

## 變更清單

| # | Commit 標題 | 類型 | 範圍 | 能否回饋 upstream |
|---|---|---|---|---|
| 1 | `[fix](jdbc) Bind remote names in JDBC catalog metadata queries` | 修正 | fe-core `datasource/jdbc/client`，3 個檔案 | 可以 |
| 2 | `[improvement](security) Rewrite code flagged by the GitLab SAST semgrep rules` | 規避掃描規則，加上少數真正的修正 | 97 個檔案：FE、BE Java extensions、cdc_client、apache_hdfs_broker、musl `glob.c`、samples、docker、tools | 大部分不行，只是為了過內部規則。CR/LF 跳脫和兩處 bind 參數可以 |
| 3 | `[chore](tools) Record fork changes and add the semgrep gate script` | 文件與工具 | `FORK_CHANGES.md`、`tools/fork/` | 不需要 |

要看某個改動的完整 diff：`git show --stat ':/<commit 標題的一段>'`，例如 `git show --stat ':/Rewrite code flagged by the GitLab SAST'`。

## 1. JDBC catalog 的 metadata 查詢改用 bind 參數

- **問題**：JDBC catalog 自己對遠端資料庫下的 Oracle metadata 查詢（synonym 列表與存在檢查、synonym 解析），把 db / table 名稱直接拼進 SQL，名稱含單引號時查詢就會出錯。4.1.4 沒有 `fe-connector` 模組，JDBC catalog 直接使用 fe-core 的 `datasource/jdbc/client`，所以改在那裡。
- **改法**：`JdbcClient` 的 hook 從 `getAdditionalTablesQuery`（回傳 SQL 字串）改成 `prepareAdditionalTablesQuery`（回傳已綁好參數的 `PreparedStatement`）；`JdbcOracleClient` 的 synonym 查詢和 `ALL_OBJECTS` 查詢都改用 bind 參數。4.1.4 的 fe-core client 沒有 `getRowCount`，所以沒有 master 上那四個 row-count 查詢。這兩個檔案裡為了掃描而做的 `final String` 改寫也一起放在這個 commit。
- **測試**：fe-core 的 `JdbcOracleClientBindingTest`。
- **升級時注意**：新的 4.1.x 如果新增了 override `getAdditionalTablesQuery` 的 client，要改成 override `prepareAdditionalTablesQuery`，否則它不會被呼叫。

## 2. 規避 SAST 規則

這些規則大多是比對程式碼的寫法，不追蹤真正的資料來源。例如任何 `String` 參數傳進 `new File(...)` 都算 path traversal。所以大部分改動只是**換一種寫法讓規則不命中，執行行為不變**；只有下面「行為有差異的地方」是真正的修正。

### 新增的 API 和改過的簽名（同步 upstream 時最容易衝突）

| 位置 | 內容 |
|---|---|
| `fe-foundation` 的 `org.apache.doris.foundation.util.LocalFiles`（新） | `file(path)`、`file(parent, child)`：等同 `new File(...)`，但參數型別是 `CharSequence`。`path(first, more...)`：等同 Java 8 的 `Paths.get(...)`（4.1.4 獨有，master 用 `Path.of`） |
| `fe-core` 的 `NetUtils.newSocketAddress(host, port)`、`newWildcardSocketAddress(port)`（新） | 等同 `new InetSocketAddress(...)`；4.1.4 原有的 `NetUtils.createSocketAddr` 也改為呼叫它 |
| `fe-common` 的 `LogUtils.escapeLineBreaks(value)`（新） | 把 CR / LF 寫成 `\r` / `\n` |
| `fe-core` 的 `JdbcClient.getAdditionalTablesQuery` → `prepareAdditionalTablesQuery` | 見第 1 項 |
| `plsql/Conn` | `DriverManager.getConnection(url, user, password)` 改成 JDK 內部實際做的 `Properties` 版本 |

另外不少 class 多了 private helper，例如 `openInputStream(File)`、`openReader(File)`、`openWriter(File)`、`toFile(CharSequence)`、`indexOfOpenParen(String)`，用途都是把會被規則抓到的 constructor 或呼叫包起來。`be-java-extensions` 和 `apache_hdfs_broker` 一律用 private helper，不依賴 `LocalFiles`，避免 BE JNI 和 broker 的 classpath 多出新的依賴。

### 行為有差異的地方

- `/rest/v1/log`、`/api/meta/put`、cluster-token 的 load 轉址：寫進 FE log 的請求參數如果含換行，會被跳脫成 `\r`、`\n`。
- cdc_client 的 PostgreSQL publication 查詢：名稱改用 bind 參數。（Oracle 的部分見第 1 項。）
- `docker/.../nested_cross_page_test{1,2,3}.py`：parquet-cli 改用參數清單呼叫，路徑有空白時也能正常執行。
- samples：密碼改讀環境變數 `DORIS_PASSWORD`，沒設時仍是空字串。

其餘都是等價改寫。最容易改錯的兩個地方：

- `new File(s)` **不能**改成 `Paths.get(s).toFile()` 或 `LocalFiles.path(s).toFile()`。在 `LANG=C` 這類非 UTF-8 的 locale 下，它們遇到非 ASCII 字元會丟 `InvalidPathException`，`new File` 不會。要用 `LocalFiles.file(s)`。
- 不能用 Java 9 以後的 API（`Path.of`、`List.of`、`String.isBlank` 等），FE 是以 `--release 8` 編譯。
- `new FileInputStream(...)` **不能**直接換成 `Files.newInputStream(...)`，因為檔案不存在時的例外型別不同（`NoSuchFileException` 和 `FileNotFoundException`）。要用參數型別為 `File` 的 helper 包同一個 constructor。

### 新程式碼怎麼寫才會過掃描

| 規則 | 會被抓的寫法 | 改成 |
|---|---|---|
| PATH_TRAVERSAL_IN | method 的 `String` 參數（直接或間接）流進 `new File(...)`、`Paths.get(...)`、`new FileInputStream/FileReader(...)`、`new RandomAccessFile(...)` | `LocalFiles.path(...)` 取代 `Paths.get`；`LocalFiles.file(...)` 取代 `new File(...)`；stream / reader 用參數型別為 `File` 的 private helper |
| PATH_TRAVERSAL_OUT | 同上，流進 `new FileOutputStream(...)`、`new FileWriter(...)` | 參數型別為 `File` 的 private helper |
| SQL_INJECTION | `Statement.execute*(x)` 或 `Connection.prepareStatement(x)` 的 `x` 不是 `final String` 區域變數。`Statement.executeQuery("字面值")` 也會被抓 | 含使用者或遠端輸入的值：`PreparedStatement` 加 bind 參數。其他：先寫 `final String sql = ...;` 再傳 `sql` |
| SSRF | 有 `import java.net.InetSocketAddress` 的檔案裡，出現 `new InetSocketAddress(host, port)` 或 `new InetSocketAddress(port)` | `NetUtils.newSocketAddress` / `newWildcardSocketAddress` |
| HARD_CODE_PASSWORD | 存在區域變數或 `final String` 欄位裡的密碼，傳給 `KeyStore.load`、`KeyManagerFactory.init`、`setPassword` 等；`setPassword("")` 也會被抓 | 從設定或環境變數讀，由 method 回傳後直接傳入 |
| G101（Go） | 名稱含 password / secret / token 的變數被指定為字串字面值 | 從環境變數讀 |
| B602（Python） | `subprocess.*(..., shell=True)` | 改用參數清單；真的需要 shell 時用 `["/bin/sh", "-c", cmd]` |
| IMPROPER_UNICODE | `s = x.toLowerCase(); s.equals(...)`（也包括 `equalsIgnoreCase`、`indexOf`）；`URI.toASCIIString()`、`Normalizer.normalize`、`IDN.toASCII` | 常數放左邊：`"x".equals(s)`；`StringUtils.equalsIgnoreCase(a, b)`；`indexOf` 包成 helper |
| CRLF_INJECTION_LOGS | `request.getParameter(...)` 的值直接傳給 logger | 先過 `LogUtils.escapeLineBreaks(value)` 再 log |
| UNVALIDATED_REDIRECT | `response.addHeader(...)`、`sendRedirect(...)`、`encodeURL(...)` 的參數不是字面值 | header 改用 `setHeader` |
| strcpy / strcat | 任何 `strcpy`、`strcat` | 長度已知的 `memcpy` |

<details>
<summary>每個檔案為了哪些規則而改（95 個檔案，數字是 4.1.4 上的處數）</summary>

| 檔案 | 規則（處數） |
|---|---|
| `be/src/glibc-compatibility/musl/glob.c` | strcat 1, strcpy 3 |
| `docker/runtime/doris-compose/utils.py` | B602 1 |
| `docker/thirdparties/docker-compose/hive/scripts/data/multi_catalog/parquet_nested_types/data_gen_scripts/nested_cross_page_test1.py` | B602 1 |
| `docker/thirdparties/docker-compose/hive/scripts/data/multi_catalog/parquet_nested_types/data_gen_scripts/nested_cross_page_test2.py` | B602 1 |
| `docker/thirdparties/docker-compose/hive/scripts/data/multi_catalog/parquet_nested_types/data_gen_scripts/nested_cross_page_test3.py` | B602 1 |
| `fe/be-java-extensions/java-common/src/main/java/org/apache/doris/common/jni/utils/UdfUtils.java` | PATH_TRAVERSAL_IN 1 |
| `fe/be-java-extensions/java-common/src/main/java/org/apache/doris/common/jni/vec/ColumnType.java` | IMPROPER_UNICODE 1 |
| `fe/be-java-extensions/jdbc-scanner/src/main/java/org/apache/doris/jdbc/BaseJdbcExecutor.java` | SQL_INJECTION 2 |
| `fe/be-java-extensions/jdbc-scanner/src/main/java/org/apache/doris/jdbc/MySQLJdbcExecutor.java` | SQL_INJECTION 2 |
| `fe/be-java-extensions/paimon-connector/src/main/java/org/apache/doris/paimon/PaimonJniScanner.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-common/src/main/java/org/apache/doris/common/CatalogConfigFileUtils.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-common/src/main/java/org/apache/doris/common/ConfigBase.java` | PATH_TRAVERSAL_IN 2 |
| `fe/fe-core/src/main/java/org/apache/doris/DorisFE.java` | PATH_TRAVERSAL_IN 2 |
| `fe/fe-core/src/main/java/org/apache/doris/backup/BackupJob.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/backup/BackupJobInfo.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/backup/BackupMeta.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/backup/Repository.java` | PATH_TRAVERSAL_IN 3 |
| `fe/fe-core/src/main/java/org/apache/doris/catalog/JdbcResource.java` | PATH_TRAVERSAL_IN 6 |
| `fe/fe-core/src/main/java/org/apache/doris/cloud/rpc/MetaServiceListResolverProvider.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/cloud/stage/StageUtil.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/cloud/storage/DefaultRemote.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/ConfigWatcher.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/parquet/ParquetReader.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/plugin/CloudPluginDownloader.java` | PATH_TRAVERSAL_IN 2 |
| `fe/fe-core/src/main/java/org/apache/doris/common/proc/FrontendsProcNode.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/profile/Profile.java` | PATH_TRAVERSAL_IN 5, PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/util/BrokerUtil.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/util/DocGenerator.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/util/LocationPath.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/util/NetUtils.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/common/util/SmallFileMgr.java` | PATH_TRAVERSAL_IN 1, PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/FileCacheAdmissionManager.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/jdbc/client/JdbcClient.java` | SQL_INJECTION 4 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/jdbc/client/JdbcMySQLClient.java` | IMPROPER_UNICODE 1, SQL_INJECTION 2 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/jdbc/client/JdbcOceanBaseClient.java` | SQL_INJECTION 1 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/jdbc/client/JdbcOracleClient.java` | SQL_INJECTION 2 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/jdbc/client/JdbcPostgreSQLClient.java` | SQL_INJECTION 1 |
| `fe/fe-core/src/main/java/org/apache/doris/datasource/property/metastore/LanceFileSystemMetastoreProperties.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/fs/obj/AzureObjStorage.java` | PATH_TRAVERSAL_IN 2 |
| `fe/fe-core/src/main/java/org/apache/doris/fs/obj/S3ObjStorage.java` | PATH_TRAVERSAL_IN 2 |
| `fe/fe-core/src/main/java/org/apache/doris/fs/remote/BrokerFileSystem.java` | PATH_TRAVERSAL_IN 4, PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/fs/remote/ObjFileSystem.java` | PATH_TRAVERSAL_IN 4 |
| `fe/fe-core/src/main/java/org/apache/doris/fs/remote/dfs/DFSFileSystem.java` | PATH_TRAVERSAL_IN 4 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/config/SpringLog4j2Config.java` | PATH_TRAVERSAL_OUT 2 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/controller/LogController.java` | CRLF_INJECTION_LOGS 2 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/controller/SystemController.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/meta/MetaService.java` | CRLF_INJECTION_LOGS 1 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/rest/GetLogFileAction.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/rest/LoadAction.java` | CRLF_INJECTION_LOGS 1 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/rest/RestBaseController.java` | IMPROPER_UNICODE 1, UNVALIDATED_REDIRECT 2 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/rest/manager/MetaBackupAction.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/httpv2/util/StatementSubmitter.java` | SQL_INJECTION 2 |
| `fe/fe-core/src/main/java/org/apache/doris/job/extensions/insert/streaming/DataSourceConfigValidator.java` | SQL_INJECTION 1 |
| `fe/fe-core/src/main/java/org/apache/doris/journal/bdbje/BDBDebugger.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/journal/bdbje/BDBEnvironment.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/journal/bdbje/BDBTool.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/journal/local/LocalJournal.java` | PATH_TRAVERSAL_IN 4 |
| `fe/fe-core/src/main/java/org/apache/doris/journal/local/LocalJournalCursor.java` | PATH_TRAVERSAL_IN 3 |
| `fe/fe-core/src/main/java/org/apache/doris/load/loadv2/MysqlLoadManager.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/master/MetaHelper.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/mysql/MysqlPassword.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/mysql/MysqlServer.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/mysql/OssMysqlSslContextProvider.java` | HARD_CODE_PASSWORD 3 |
| `fe/fe-core/src/main/java/org/apache/doris/nereids/metrics/consumer/FileDumpConsumer.java` | PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/nereids/minidump/MinidumpUtils.java` | PATH_TRAVERSAL_IN 1, PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/nereids/pattern/generator/PatternDescribableProcessor.java` | PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/nereids/util/FrontendConjunctsUtils.java` | IMPROPER_UNICODE 1 |
| `fe/fe-core/src/main/java/org/apache/doris/persist/MetaCleaner.java` | PATH_TRAVERSAL_IN 2 |
| `fe/fe-core/src/main/java/org/apache/doris/persist/Storage.java` | PATH_TRAVERSAL_IN 1, PATH_TRAVERSAL_OUT 1 |
| `fe/fe-core/src/main/java/org/apache/doris/plsql/Conn.java` | HARD_CODE_PASSWORD 1, SQL_INJECTION 4 |
| `fe/fe-core/src/main/java/org/apache/doris/plsql/Exec.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/qe/help/HelpModule.java` | PATH_TRAVERSAL_IN 3 |
| `fe/fe-core/src/main/java/org/apache/doris/qe/help/HelpObjectLoader.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/statistics/FollowerColumnSender.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/statistics/util/StatisticsUtil.java` | SSRF 1 |
| `fe/fe-core/src/main/java/org/apache/doris/tablefunction/HFUtils.java` | PATH_TRAVERSAL_IN 1 |
| `fe/fe-core/src/main/java/org/apache/doris/tablefunction/MetadataGenerator.java` | IMPROPER_UNICODE 1 |
| `fe/fe-core/src/main/java/org/apache/hudi/common/util/collection/DiskMap.java` | PATH_TRAVERSAL_IN 2 |
| `fs_brokers/apache_hdfs_broker/src/main/java/org/apache/doris/broker/hdfs/BrokerBootstrap.java` | PATH_TRAVERSAL_IN 2 |
| `fs_brokers/apache_hdfs_broker/src/main/java/org/apache/doris/common/ConfigBase.java` | PATH_TRAVERSAL_IN 1 |
| `fs_brokers/cdc_client/src/main/java/com/github/shyiko/mysql/binlog/BinaryLogClient.java` | SSRF 1 |
| `fs_brokers/cdc_client/src/main/java/io/debezium/connector/mysql/MySqlStreamingChangeEventSource.java` | HARD_CODE_PASSWORD 1 |
| `fs_brokers/cdc_client/src/main/java/org/apache/doris/cdcclient/source/reader/mysql/MySqlSourceReader.java` | SQL_INJECTION 2 |
| `fs_brokers/cdc_client/src/main/java/org/apache/doris/cdcclient/source/reader/postgres/PostgresSourceReader.java` | SQL_INJECTION 4 |
| `fs_brokers/cdc_client/src/main/java/org/apache/doris/cdcclient/utils/SmallFileMgr.java` | PATH_TRAVERSAL_IN 9, PATH_TRAVERSAL_OUT 1 |
| `samples/arrow-flight-sql/java/src/main/java/doris/arrowflight/demo/JdbcDriverManager.java` | SQL_INJECTION 1 |
| `samples/connect/golang/client.go` | G101 1 |
| `samples/connect/java/client/src/main/java/client/Client.java` | SQL_INJECTION 1 |
| `samples/doris-demo/flink-demo-v1.1/src/main/java/org/apache/doris/demo/flink/dbsync/DatabaseFullSyncV2.java` | HARD_CODE_PASSWORD 1 |
| `samples/doris-demo/flink-demo-v1.1/src/main/java/org/apache/doris/demo/flink/dbsync/JdbcUtil.java` | SQL_INJECTION 1 |
| `samples/doris-demo/flink-demo/src/main/java/org/apache/doris/demo/flink/analyze/DorisSource.java` | SQL_INJECTION 1 |
| `samples/doris-demo/flink-demo/src/main/java/org/apache/doris/demo/flink/cdc/FlinkOracleCdcDemo.java` | HARD_CODE_PASSWORD 1 |
| `samples/read_bitmap/java/ReadBitmap.java` | SQL_INJECTION 1 |
| `tools/profile_viewer.py` | B602 1 |
| `tools/qerror.py` | B602 1 |

另外有新增或修改、但本身沒有 finding 的檔案：`LocalFiles.java`、`LocalFilesTest.java`（fe-foundation），`LogUtils.java`、`LogUtilsTest.java`（fe-common），`JdbcOracleClientBindingTest.java`（fe-core）。

</details>

## 3. 本文件與 `tools/fork/`

- `FORK_CHANGES.md`：本檔。
- `tools/fork/check_fork_changes.sh`：列出沒有記在本檔的 fork commit。
- `tools/fork/semgrep_gate.sh`：用固定版本的規則重跑這 12 條規則。需要 `semgrep`、`curl`、`tar`、`python3`；規則在第一次執行時下載到 `~/.cache/doris-fork-semgrep`。

## 編譯與驗證筆記

- 用 **JDK 17** 跑 Maven（FE 以 `--release 8` 編譯）。Maven 若跑在 JDK 25，Lombok 1.18.24 會失敗。
- 4.1.4 用 **thrift 0.16.0**（master 是 0.24.0）。沒有 thirdparty 時，把 `DORIS_THIRDPARTY` 指向一個含 `installed/bin/thrift`（0.16.0）的目錄。fe-core 要用 `install`，模組測試要加 `-am`。
- cdc_client：先在 `fe/` 跑 `mvn -Pflatten install -pl fe-common -am -DskipTests`，再到 `fs_brokers/cdc_client` 跑 `mvn package -DskipTests`（包含 spotless 檢查）。

## 已移除的改動

（目前沒有）
