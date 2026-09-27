# 汉化维护手册（简体中文）

本文件是这份 **Know Your Constellation 简体中文分叉**的汉化作业说明：文本放在哪里、
构建/渲染侧的硬性约束、字库缺字怎么处理、上游更新后如何重新汉化与验收。
上游英文原始项目：<https://github.com/CowboyBingus/KnowYourConstellation>。

术语依据：社区汉化包 `Know-Your-Constellation-Rows-v3.12-zh-CN.zip` 的《汉化术语说明》
（其对照表对齐自游戏官方简体中文语言资源）。本分叉沿用其官方译名，例外见 §5。

---

## 0. 上游更新后的一分钟清单

1. 合并上游英文改动，冲突基本集中在"显示文本"的 4 个文件（§1）。
2. 逐个把新增/被还原成英文的显示串按 §5 译回中文，**不要动已有 ID 编号**。
3. `src/heavy_data.lua` 若被上游重新生成，把它 3 个标签按 §5 改回中文。
4. `python scripts/build.py --allow-untested` 与 `python scripts/build.py --rows --allow-untested`。
   离线测试会拦住"漏译"和"用了缺字字形"（§3、§4）。
5. `python scripts/privacy_audit.py --zip releases\<两个包>`。
6. 进游戏：日志 `EnemyIntelligence.log`（状态/卡死）、`EnemyIntelligenceFont.log`（缺字清单）。
   缺字清单应为 `font missing 0 ` 或只剩已知项；出现新字就按 §4 换字。
7. 新增/删除仓库文件时同步 `publication-files.json`（隐私审计按它核对清单）。

---

## 1. 汉化文本在哪里

| 文件 | 内容 | 备注 |
| --- | --- | --- |
| `src/catalogue.lua` | 31 条编组标题 + 说明（面板主体） | 数据表；ID 必须稳定，见 §6 |
| `src/model.lua` | 面板标题、重型敌人、常规部队、暂无编组情报、两条无数据说明、3 条页脚 | `M.make` 内的字符串字面量 |
| `src/heavy_data.lua` | 重型敌人名称（吐酸泰坦／蟑龙／阴霾吐酸泰坦） | **自动生成文件**，重生成会覆盖标签 |
| `scripts/build.py` | Mod 管理器显示名与描述（`LOCALIZED_*` 常量） | 见 §2 的命名约定 |
| `INSTALL-zh-CN.txt` | 随包发布的中文说明（`install_instructions`） | 打包进 ZIP 的 README 槽位 |
| `src/install.lua` | 状态/诊断日志 | **刻意保持英文**，方便对照上游排查 |
| 结构性标记 | `    //    `、`    /// END REPORT ///`、`[标题] ` | **必须保持 ASCII**，代码按它切分 |

渲染侧的三份 `display` 校验函数分别在 `src/model.lua`、`src/panel.lua`、`src/rows.lua`，
三者逻辑相同（模块彼此独立，按项目原有风格各留一份）。改校验规则要三处同改。

---

## 2. 构建与工具链事实

- **全链路 UTF-8**：`scripts/module.py:module_source` 以 UTF-8 读取 `src/*.lua`（并拒绝 BOM），
  `scripts/build.py` 以 UTF-8 写 `build/mod.wrapper.lua`，子进程输出也按 UTF-8 解码。
  LuaJIT 把字节串原样编译进字节码，中文因此无损。
- **必须加 `--allow-untested`**：汉化改变了运行时载荷，与 `TESTED_RESOURCE_SHA` 不再相等；
  这是安全闸门，不要绕过、也不要改那两个 SHA 常量去"骗过"它。
- **发布的字节码是非 GC64（`-bsdW`）**，供游戏加载器使用；若本机 LuaJIT 是 GC64
  （`ffi.abi('gc64')==true`，例如 Scoop 版），`build.py` 会另 dump 一份 GC64 副本仅供
  `tests/test_package.lua` 加载测试，**发布字节码不变**。
- **可复现**：`-d` 确定性 dump + 固定 ZIP 时间戳，连续两次构建的 ZIP 哈希应完全一致。
- **命名约定**：provenance 里的 `name`、`slug`、发布文件名保持 ASCII
  （`releases/Know-Your-Constellation-v3.15.zip`），管理器里显示的中文名/描述来自
  `report['localized_name']` / `report['localized_description']`。
- provenance 附带 `localization` 段：`{language, source_revision, in_game_verified, utf8_wrap}`。
- 环境变量（本机实测值）：
  `HD2_GAME_ROOT=E:\SteamLibrary\steamapps\common\Helldivers 2`、
  `HD2_LUAJIT=D:\Scoop\apps\luajit\current\bin\luajit.exe`。

---

## 3. 渲染侧的三条硬规则（都被游戏内事故验证过）

1. **文本必须是合法 UTF-8，且不含 ASCII 分号**。`display()` 拒绝非法/超长/代理区/越界序列、
   控制字符与 `;`。半角分号是预报复用字符，别用；全角标点（、。：；）没问题。
2. **绝不要把"半个 UTF-8 字符"交给引擎**。`Gui.text_extents` 逐字节测量前缀曾导致
   **游戏在面板打开时卡死**；现在 caret 只在字符边界测量（`panel.lua:character`、
   `rows.lua:step`），滚动窗口的切口也会对齐到完整字符。测试里有 `complete()` 断言：
   任何原生文本调用收到不完整序列都会失败。
3. **无空格文本按字符换行**（`rows.lua:M.wrap`）。中文整句没有空格，按字节拆会把字切成碎片。

---

## 4. 字库字形覆盖（问号问题）

面板使用的字体/材质/图集全部取自**当前 locale 的原生正文字体**（`presentation.lua`），
所以**游戏文本语言必须是简体中文**，否则中文整体画不出来。

字库通常是"按游戏自身文本裁剪"的子集字体，游戏文本里没有的字就没有字形，引擎会改画
notdef 标记 —— 玩家看到的就是**问号**。

- **探针**：渲染器对每个画出来的字符探测一次（私用区码位一定无字形，其墨迹宽度即缺字标记宽度；
  宽度相同者即缺字），结果写入**独立日志**：
  `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\EnemyIntelligenceFont.log`
  格式：`font missing <个数> <字符…> font=<字体哈希>`。它是累积的，最后一次写入即完整清单。
- **已知缺字（build 25327279，简中正文 face `fbb35bee675f2295`）**：`汁` (U+6C41)。
  因此 Bile 一律作 **吐酸**（与「吐酸泰坦／阴霾吐酸泰坦」一致），全篇不出现 `汁`。
- **换字规则**：优先换用**已验证能显示**的字（即清单里没报过的字），不要引入未验证的新字；
  新词上线前先看 `EnemyIntelligenceFont.log`。注意中日汉字共享码位，**"换成日语写法"无效**。
- **离线守卫**：`tests/test_resolve.lua` 的 `unavailable` 列表与 `tests/test_heavy.lua`
  会对目录/面板文案/标签检查缺字；`汁` 一旦写回，离线测试即失败。
  若某次游戏更新后字库补上了 `汁`（用探针确认），可恢复官方写法并同步删掉该列表项。

---

## 5. 术语表

### 5.1 界面串（`src/model.lua`）

| 英文（上游） | 中文 |
| --- | --- |
| FORECAST // INTEL AND RECON | 敌情预测 // 情报与侦察 |
| HEAVY ENEMIES | 重型敌人 |
| STANDARD FORCES | 常规部队 |
| No special constellation selected | 未选中特殊敌军编组 |
| COMPOSITION UNAVAILABLE | 暂无编组情报 |
| No resolved composition for this mission | 无法确定此任务的敌军编组 |
| Possible encounters. Spawns are not guaranteed. | 可能遭遇的敌人，不保证实际出现。 |
| Base forecast. Special enemy intel is incomplete. | 基础预测：特殊敌人情报尚不完整。 |
| Composition traits. Units vary with difficulty. | 编组特征：兵种随难度变化。 |
| Unit intelligence unavailable | 暂无兵种情报 |

### 5.2 重型敌人标签（`src/heavy_data.lua`）

| 资源哈希 | 英文 | 中文 |
| --- | --- | --- |
| `0x9e2e17f2ccccafdd` | Bile Titans | 吐酸泰坦 |
| `0x960b48a421a3faaa` | Dragonroaches | 蟑龙 |
| `0xd37e8d120d2836e3` / `0xef04cb84d097a497` | Gloom Bile Titans | 阴霾吐酸泰坦 |

### 5.3 管理器文案（`scripts/build.py`）

| 常量 | 值 |
| --- | --- |
| `LOCALIZED_NAME` | 敌情预测 |
| `LOCALIZED_ROWS_NAME` | 敌情预测·分行显示 |
| `LOCALIZED_SUMMARY` | 在银河战争地图及任务简报中显示敌军编组与可能遭遇的敌人，方便选择武装配置。 |
| `LOCALIZED_ROWS_SUMMARY` | 采用静态分行显示，支持中文换行。 |
| `LOCALIZED_TAIL` | 仅在本机显示。需要另行安装 Bingus Shared Loader v12 或更新版本。 |
| `LOCALIZED_LAST` | 仅启用一种敌情预测版本；不保证预测敌人实际出现。 |

### 5.4 编组条目（`src/catalogue.lua`，当前 30 条已汉化 + 1 条待定）

| ID | 标题 | 说明 |
| --- | --- | --- |
| 1 | 吐酸虫群 | 吐酸喷涌虫、吐酸吐沫虫与吐酸武斗虫 |
| 2 | 重甲虫群 | 虫窝护卫与强袭虫群 |
| 3 | 追猎虫群 | 追猎虫与猛扑虫 |
| 4 | 飞行虫群 | 暂无兵种情报 |
| 5 | 轻型虫群 | 食腐虫、武斗虫与虫族指挥官 |
| 6 | 虫族育巢 | 抚育喷涌虫与食腐虫群 |
| 7 | 终结族混编虫群 | 混编地面部队 |
| 8 | 超级掠食者 | 强化追猎虫变种 |
| 9 | 阴霾变种 | 阴霾变异的武斗虫、追猎虫与吐酸泰坦 |
| 10 | 掘地虫群 | 爆裂武斗虫、爆裂喷涌虫与爆裂强袭虫 |
| 11 | 蟑龙活动 | 任务修正启用蟑龙 |
| 12 | 尖啸虫修正 | 暂无兵种情报 |
| 13 | 突击部队 | 近战步兵与突击集群 |
| 14 | 方阵部队 | 重武器士兵与压制单位 |
| 15 | 炮兵部队 | 火箭兵与炮兵集群 |
| 16 | 空中编组 | 暂无兵种情报 |
| 17 | 装甲纵队 | 侦察纵步者与坦克集群 |
| 18 | 机器人混编部队 | 混编步兵与装甲部队 |
| 19 | 跳跃突击部队 | 跳跃步兵与跳跃士兵 |
| 20 | 生化人部队 | 生化人精锐与攻城机兵 |
| 21 | 炮舰修正 | 暂无兵种情报 |
| 22 | 象牙军团 | 喷火步兵与霰弹枪兵 |
| 23 | 霸王虫修正 | 暂无兵种情报 |
| 24 | 光能者残部 | 暂无兵种情报 |
| 25 | 战争机器修正 | 暂无兵种情报 |
| 26 | 光能者工程部队 | 持杖单位、喷气单位与外骨骼机甲 |
| 27 | 光能者入侵部队 | 无票者、监视者与猎杀器 |
| 28 | 光能者收割部队 | 无票者、光束单位与猎杀器 |
| 29 | 躯体畸变 | 无票者与躯体畸变变种 |
| 30 | 超级地球武装部队支援 | 友军士兵与专业人员 |
| 31 | *(待定)* | 上游 `HORDE FORCES` / `Horde-only mission composition` |

> **ID 31**：对应本构建新增的 native tag 1（`HordeOnly` 任务模式），`resolve.from_native(1)==31`。
> 该模式在当前构建里未实际出现，上游给的也是英文，词条因此**保持英文**并作为
> `tests/test_resolve.lua` 中唯一显式例外（`pending={[31]=true}`）。定词后把例外删掉，
> 离线守卫会自动接管。候选：「虫群部队／集群部队」+「仅虫群任务编组」。

### 5.5 官方兵种名（译"说明"栏时优先使用）

食腐虫（Scavengers）、武斗虫（Warriors）、追猎虫（Hunters）、猛扑虫（Pouncers）、
虫窝护卫（Hive Guards）、强袭虫（Chargers）、虫族指挥官（Brood Commanders）、
抚育喷涌虫（Nursing Spewers）、胆汁喷涌虫（Bile Spewers）、胆汁吐沫虫（Bile Spitters）、
吐酸武斗虫（Bile Warriors）、吐酸泰坦（Bile Titans）、蟑龙（Dragonroaches）、
监视者（Overseers）、无票者（Voteless）、猎杀器（Harvesters）、侦察纵步者（Scout Striders）、
炮舰（Gunships）、霸王虫（Hive Lords）、爆裂武斗虫（Rupture Warriors）、
爆裂喷涌虫（Rupture Spewers）、爆裂强袭虫（Rupture Chargers）；Gloom 作「阴霾」，Cyborg 作「生化人」。

> 官方对两种 Bile 单位写作「胆汁喷涌虫／胆汁吐沫虫」，但本构建字库没有 `汁`（§4），
> 故全篇统一作「吐酸」。这是**有意偏离**，而不是译误；字库补上后可恢复。

---

## 6. 上游更新后的合并流程

1. `git fetch upstream && git merge upstream/master`（或按你自己的分支策略 rebase）。
   冲突几乎必然落在 §1 表格里的显示文件上——**保留上游的结构/逻辑，重新套用中文**。
2. **新增编组/标签**：看上游 `docs/CONSTELLATIONS.md` 新增的 native tag，在
   `src/catalogue.lua` 追加中文条目。**绝不要重排既有 ID**：
   `resolve.from_native` 依赖 `tag 1 → 31`、`tag n → n-1` 的映射，
   `tests/test_mission.lua` / `tests/test_resolve.lua` 会验证。
3. **`src/heavy_data.lua` 重生成会丢中文标签**，重新套用 §5.2。
4. **`scripts/build.py` 的 `LOCALIZED_*` 常量**：上游若改了英文 SUMMARY/描述，同步改中文。
5. 若上游改了 `scripts/*.py` 的编码路径（`module_source`、`encoding='utf-8'`、
   `gc64()` 兼容分支），注意别让 ASCII 假设回归——那正是最初"无法构建"的根因。
6. 版本号/发布名：保持 ASCII 词干（`Know-Your-Constellation-<rev>.zip`），
   管理器中文名里的版本号由 `REVISION` 生成。
7. 新增文件记得登记 `publication-files.json`；行尾保持 LF（`.editorconfig`），
   Windows 编辑器容易写成 CRLF，`git diff` 会警告。

---

## 7. 验收清单

**离线（全绿才算完）**

```powershell
$luajit = 'D:\Scoop\apps\luajit\current\bin\luajit.exe'
foreach ($n in 'resolve','panel','install','mission','heavy','presentation','rows') {
  & $luajit "tests\test_$n.lua" 'src'; "test_$n exit=$LASTEXITCODE"
}
python scripts\build.py --allow-untested            # 含全部套件 + 打包
python scripts\build.py --rows --allow-untested
python scripts\privacy_audit.py --zip releases\Know-Your-Constellation-v3.15.zip `
  --zip releases\Know-Your-Constellation-Rows-v3.15.zip
Get-FileHash releases\*.zip -Algorithm SHA256       # 记录/比对可复现性
```

测试里已经固化的汉化约束：目录/面板文案无 ASCII 字母（`[31]` 例外）、无缺字字形、
文本是合法 UTF-8、原生调用只收到完整字符、重型标签已汉化。

**游戏内（每次改文案后至少一次）**

1. 游戏文本语言 = 简体中文；装包 → Purge/Deploy → 进游戏。
2. 地图悬停任务 + 简报各看一次（滚动版看滚动，分行版看每一行是否完整、有无问号）。
3. 看两个日志：
   - `EnemyIntelligence.log`：最后一行应为 `visible …`（若为 `hidden` 只是面板当时隐藏，
     不代表出错）；卡死时会停在 `drawing …` / `panel measuring|drawing` / `rows fitting|drawing`。
   - `EnemyIntelligenceFont.log`：`font missing <n> … font=<哈希>`；理想是 `0`。
4. `font=<哈希>` 可用来 A/B 比对"游戏语言切换后字体是否变化"。

---

## 8. 已知坑（都踩过，别再踩）

| 坑 | 症状 | 结论 |
| --- | --- | --- |
| `encoding='ascii'` 读写源码 | 构建第一步就 `UnicodeDecodeError` | 全链路 UTF-8 |
| 三份"仅 ASCII"显示守卫 | 中文让 mod 直接被禁用 | 改 `display()` 校验 UTF-8 |
| 逐字节测量 UTF-8 前缀 | **打开面板即卡死** | caret 只在字符边界测量 |
| 按字节折行/切窗口 | 半个汉字、乱码 | 按字符换行、切口对齐字符 |
| 加载器 `open_log` 以 `'w'` 打开 | 日志只剩最后一次写入，卡死无痕 | 在危险调用**之前**写"意图"面包屑；必须留存的诊断单独一份文件 |
| 显示文本用 ASCII 分号 | 与预报复用字符冲突 | 全角标点 |
| 子集字库缺字 | 个别字显示成问号 | 探针 + 换字（§4） |
| `heavy_data.lua` 是生成物 | 标签被还原成英文 | 重生成后重套 §5.2 |
| 新增文件不改 `publication-files.json` | 隐私审计/清单不一致 | 同步登记 |
| ZIP 内多塞文件 | 隐私审计按固定文件集校验会失败 | 需同时改 `scripts/privacy_audit.py` 的 `expected` 集合 |
| CRLF | `git` 警告、diff 噪音 | 保持 LF |

---

## 9. 文档与脚本索引

| 文件 | 作用 |
| --- | --- |
| `docs/LOCALIZATION-zh-CN.md` | 本手册 |
| `INSTALL-zh-CN.txt` | 面向玩家的中文安装/显示/诊断说明（随包发布） |
| `docs/TECHNICAL.md` | 运行时设计、诊断与字形覆盖原理（英文，上游文档） |
| `CONTRIBUTING.md` | 构建/验证流程（英文，上游文档） |
| `docs/CONSTELLATIONS.md` | 编组与 native tag 对照（上游文档，新增条目的依据） |
| `src/catalogue.lua` / `src/model.lua` / `src/heavy_data.lua` / `scripts/build.py` | 汉化文本所在处 |
| `tests/test_resolve.lua` / `tests/test_heavy.lua` | 汉化离线守卫（漏译、缺字） |

---

## 10. 交给 agent 的话（可直接粘贴）

> 这是 Know Your Constellation 的简体中文分叉。请先读 `docs/LOCALIZATION-zh-CN.md`，
> 按其中的"上游更新后的一分钟清单"作业。硬性要求：显示文本放在
> `src/catalogue.lua`、`src/model.lua`、`src/heavy_data.lua`、`scripts/build.py`；
> 结构性标记保持 ASCII；不要重排 catalogue ID；不要用 ASCII 分号；
> 不要引入 `EnemyIntelligenceFont.log` 报过的缺字字形（当前已知：`汁`/U+6C41，Bile 作"吐酸"）；
> 原生文本调用只能收到完整 UTF-8 字符。改完跑
> `python scripts/build.py --allow-untested` 与 `--rows --allow-untested`
> 以及 `python scripts/privacy_audit.py --zip releases\*.zip`，最后按 §7 做游戏内与日志验收。
