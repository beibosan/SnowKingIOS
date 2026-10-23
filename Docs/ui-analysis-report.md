# 雪花之王 SnowKingNative · UI 分析报告

> 分析对象：`E:\雪花之王\SnowKingNative`（原生 Android 外壳，com.snowking.assistant）
> 代码规模：17 个 Java 文件 / 约 6468 行，UI 全部代码构建（无 XML 布局）
> 报告日期：2026-08-21

---

## 一、总体结论

这是一套**「奶油风 + 线条图标」的轻拟物卡片式 UI**，设计完成度在同类游戏辅助工具中属于较高水平：

- ✅ 有完整的三主题配色系统（34 个语义化色板 token）
- ✅ 有自绘的 24×24 线条图标体系（33 枚，纯 Path 绘制，零图片资源）
- ✅ 五段式主界面布局清晰，BottomSheet 交互体系统一
- ⚠️ 存在死代码、字符图标混用、触摸目标过小、系统弹窗风格不统一等问题

**技术特征**：整个 App UI 未使用任何 XML 布局文件（仅 `styles.xml` 主题 + 1 张启动图标），所有界面在 Java 代码中通过 `LinearLayout / FrameLayout / ScrollView + GradientDrawable` 程序化搭建，`Ui.java` 充当设计令牌（Design Token）中心。

---

## 二、设计体系分析

### 2.1 三主题配色系统（Ui.java）

| 主题 | 名称 | 风格定位 | 默认 |
|---|---|---|---|
| 0 | 马卡龙色 | 高饱和糖果色（粉 #FF6B9D / 黄 #FFD93D / 天蓝 #4D96FF） | |
| 1 | 奶油大地 | 低饱和暖棕大地色（#8A5E49 / #B6925B / #788B6B） | |
| 2 | 暖茶森绿 | 低饱和绿系（#4F735B / #B58B4C / #6D9476） | ✅ 默认 |

每个主题含 **34 个语义化 token**，分五组：

| 分组 | Token | 用途 |
|---|---|---|
| 七色对 | PINK/YELLOW/MINT/SKY/LAVENDER/ORANGE/CORAL + 各自 SOFT 浅底色 | 功能色 + 柔底配对，用于图标底、标签、按钮 |
| 中性色 | CREAM / PAGE / LINE_SOFT / INK / INK_2 / CARD / FIELD | 页面底、卡片、描边、主/次文字 |
| 状态色 | STATUS_RUNNING(绿) / STATUS_CLOSED(红) / STATUS_IDLE(蓝) | 账号状态 chip |
| 行为色 | ADD_ACCENT / SORT_ACCENT / GAME_ACCENT / CURRENT_ACCENT | 新增按钮、排序、游戏栏高亮 |
| 槽位色 | SLOT_PLUS / SLOT_LABEL / SLOT_HINT / CONTROL_SOFT / GAME_BAR | 多开槽位与游戏窗口 |

- 主题通过 `SharedPreferences(snow_king_theme)` 持久化，切换后 `recreate()` 重建界面
- 浅色状态栏/导航栏适配齐全（`SYSTEM_UI_FLAG_LIGHT_STATUS_BAR`）
- ⚠️ `styles.xml` 中 `statusBarColor #FFF8F0` 为硬编码，仅与主题 0 的 CREAM 一致，主题 1/2 启动瞬间会闪一下异色状态栏

### 2.2 线条图标体系（LineIconDrawable.java）

自绘 Drawable，完全符合「线性 outline」偏好：

| 属性 | 值 |
|---|---|
| 网格 | 24×24 坐标系，自动等比缩放居中 |
| 笔触 | STROKE 描边，1.9px（24 网格下），圆角线帽/线接 |
| 数量 | 33 枚：search/plus/close/back/chevron/settings/palette/check/batch/sort/group/account/horizontal/vertical/layout/save/refresh/lock/lock-open/sync/script/bolt/volume-off/eye-off/shield/folder/cache/pause/info/file/edit/download/scan/launch/stop/trash |
| 渲染 | 抗锯齿 Paint，运行时按密度生成，零资源文件 |

**评价**：图标语言统一、风格干净，是本 UI 最大的亮点。齿轮图标用 64 段变径折线逼近，调色盘用贝塞尔曲线，细节到位。

### 2.3 形状语言

| 元素 | 圆角 | 描边 |
|---|---|---|
| 卡片 / 分组容器 | 12dp | 1dp LINE_SOFT（softStroke） |
| BottomSheet 容器 | 24dp（顶部圆角效果） | 无 |
| 大按钮（reportButton） | 12dp | 1dp LINE_SOFT |
| 小胶囊（smallPill / 分组标签） | 17dp（全圆角） | 1dp LINE_SOFT |
| 图标圆底（iconView/roundIcon） | 全圆 | 无（GameActivity 中为 2dp INK 粗描边 ⚠️ 风格跳变） |
| 状态 chip | 11dp | 无 |
| 头像 | 12dp | 无 |

整体「1dp 浅描边 + 无阴影」（`setElevation(0)` + `setStateListAnimator(null)`），属于扁平细线风格；但 `Ui.button()` 默认给 3dp INK 深色粗描边，多数调用方又覆盖回 softStroke —— 默认参数与实际风格不一致，属于遗留隐患。

---

## 三、页面结构分析

### 3.1 主界面（MainActivity，1846 行）

五段式垂直结构：

```
┌─────────────────────────────────┐
│ ① 顶部标题栏 62dp                │  标题「雪花之王」22sp + 搜索框(胶囊) + [+] + [调色盘]
├─────────────────────────────────┤
│ ② 操作工具栏 52dp                │  [批量操作] [排序]（图标+文字胶囊）
│ ③ 分组管理栏 48dp                │  账号分组 | [管理分组] [新建分组]
│ ④ 分组筛选标签 FlowLayout         │  全部 / 未分组 / 自定义…（胶囊流式换行）
│ ⑤ 账号卡片流（ScrollView）        │  84dp 卡片 × N，间距 11dp
├─────────────────────────────────┤
│ 底部导航 58dp                     │  账号 / 横向多开 / 纵向多开 / 设置
└─────────────────────────────────┘
```

**账号卡片**（84dp）信息层级：
- 左：50dp 圆角头像（账号名前 2 字 + 六色轮换柔化底色）
- 中上：名称 15sp 粗体 + 状态 chip（● 运行中/待机/已关闭，绿/蓝/红三态）
- 中下：文件路径（file 图标，中部省略）+ ◷ 相对时间（"刚刚 / N 分钟前 / MM-dd HH:mm"）

**交互模型**：
- 单击卡片 → BottomSheet 六操作（启动/关闭/改名/分组/导出/删除）
- 长按卡片 → 多选模式（标题栏切换为「已选 N 个账号」+ 批量操作按钮，返回键退出）
- BottomSheet 统一规范：46×5dp 把手 + 18sp 居中标题 + 操作行（彩色 icon 底 + 文字 + › 箭头）

### 3.2 多开窗口（MultiActivity，905 行）

- **顶部栏 40dp**：标题（模式+窗口数）+ 布局切换 + 触摸同步锁 + 关闭
- **横向多开**：自适应行规则（1→[1]，2→[1,1]，4→[2,2]，5→[2,1,2]…），单行窗高 250dp / 双列 142dp，窗口内嵌 16:9 LandscapeFrame
- **纵向多开**：固定 4 槽位，三种模式循环切换——
  - 模式 1「槽位」：4 个标签页 + 单窗口 606dp 大视口
  - 模式 2「网格」：2×2 均分（318dp/格）
  - 模式 3「焦点」：上排 3 小窗（176dp）+ 下方主窗（560dp），点击小窗提升为焦点
- **窗口微栏** 18dp：● 状态点 + 账号名（8-10sp）+ 同步锁 + 关闭
- 触摸同步：矩阵缩放镜像 MotionEvent 到其余窗口，可全局开关、逐窗口豁免
- 工程细节出色：WebView 错峰加载（1.2s 间隔）、登录看门狗（60s）、渲染进程崩溃自愈、后台暂停渲染

### 3.3 单开窗口（GameActivity，537 行）

- **工具栏 48dp**：账号名（点击弹出切换面板）+ [阵容保存] 黄色胶囊 + 刷新 + 关闭
- 顶部 3dp 进度条（主题 SKY 色），加载完成自动隐藏
- **账号热切换面板**：顶部下拉覆盖层（半透明遮罩 `argb(150,20,24,22)`），支持分组筛选 + 当前账号高亮（MINT_SOFT 底 + 「当前」标签），切换走 JS 热替换（20 次×250ms 重试，失败回退整页重载）
- 返回键逻辑：遮罩 → WebView 后退 → 退出，层级正确

### 3.4 设置页（SettingsActivity，607 行）

经典分组列表（4 组）：

| 分组 | 内容 |
|---|---|
| 功能设置 | 脚本管理(导航行) + 十殿加速/阵容切换保存/声音关闭/隐藏弹窗/安全识别（开关行） |
| 文件与存储 | 文件导出位置（SAF 目录选择） |
| 游戏容器 | 资源缓存 / 后台暂停 |
| 关于 | 版本信息 v1.2.2 · build 2 |

- 行高 72dp，icon 盒 32dp（柔色底+INK 图标），Switch 定制：开=MINT 轨道 / 关=CORAL_SOFT 轨道、白色滑块
- 脚本管理为页内二级视图（非新 Activity），返回键逐层回退；内置/外置脚本分组，外置脚本带安全扫描状态（风险脚本拦截标红）

---

## 四、设计规范提取（可直接复用）

| 类别 | 规范 |
|---|---|
| 页面骨架 | 标题栏 62 / 内容 padding 16,7,16,24 / 底栏 58（dp） |
| 卡片 | 高 84、圆角 12、softStroke 1dp、间距 11 |
| 图标 | 24 网格、1.9px 描边、圆帽；常用尺寸 16/18/19/20/22 |
| 字号阶梯 | 8-10（微栏/导航）→ 11（辅助）→ 12-13（正文）→ 14-15（标题）→ 18-23（数字/Sheet 标题） |
| 胶囊 | 高 32-38、圆角 17、选中=主题粉/白字 |
| BottomSheet | 圆角 24、把手 46×5、dimAmount 0.4、底部贴边 MATCH_PARENT |
| 头像色板 | PINK/SKY/MINT/ORANGE/LAVENDER/CORAL 六色按 id.hash 轮换，底色=soften()（RGB 各通道 225+30% 混合） |

---

## 五、问题清单（按严重度）

| # | 级别 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| 1 | 🔴 功能 | **死代码**：`buildHeader()`（蓝渐变头 + V5.8.6 角标）、`buildStats()`（统计条）、`avatarBackground()`（六色渐变头像）、MainActivity 的 `divider()`/`iconButton()` 均未被调用 | MainActivity | 删除或恢复使用；约 80 行可清理 |
| 2 | 🟠 一致性 | **字符图标与线条图标混用**：状态 chip 用「●」、时间用「◷」、Sheet 箭头用「›」、旧 header 用「⚙」emoji | 多处 | 统一替换为 LineIconDrawable（已有 dot/chevron 可复用） |
| 3 | 🟠 一致性 | **系统 AlertDialog 与定制 BottomSheet 风格割裂**：改名/删除/分组管理/角色选择均为系统默认弹窗，无圆角无主题色 | MainActivity/Settings | 迁移到 sheetContainer 体系 |
| 4 | 🟠 可用性 | **多开窗口微栏触摸目标过小**：栏高 18dp、图标 16dp，远低于 44dp 无障碍建议；账号名仅 8sp | MultiActivity | 栏高≥28dp，图标≥20dp，或加大点击热区 |
| 5 | 🟡 视觉 | GameActivity 工具栏图标用 **2dp INK 粗黑描边**，与其他页面「1dp 浅描边」风格跳变 | GameActivity.roundIcon | 去掉 stroke 或改 softStroke |
| 6 | 🟡 视觉 | Switch 关闭态轨道用 CORAL_SOFT（红系），红色通常表"危险/删除"，表"关闭"易引起歧义 | SettingsActivity | 改用 LINE_SOFT / FIELD |
| 7 | 🟡 健壮 | 主题切换 `recreate()` 整页闪屏；`styles.xml` 状态栏色硬编码 #FFF8F0 仅匹配主题 0 | Ui / styles.xml | 状态栏色改为随主题动态设置（已在 onCreate 做了，可删 XML 硬编码） |
| 8 | 🟡 健壮 | `Ui.button()` 默认 3dp INK 粗描边，几乎全部调用方再覆盖回 softStroke —— 默认值与设计语言背离 | Ui.java:206 | 默认改为 softStroke |
| 9 | 🔵 细节 | 多选模式工具栏「批量操作」按钮固定 76dp 宽，长文案/大字体下可能溢出 | MainActivity | 改 wrap_content + minWidth |
| 10 | 🔵 细节 | 无深色模式；三套主题均为浅色 | Ui | 如需夜间场景可加暗色 palette（低优先） |

---

## 六、版本演进观察（结合备份目录 APK 命名）

从 1.0.12 → 1.0.32 共 40+ 个构建，UI 迭代主线清晰：

```
图标对齐(12) → 精细图标(13) → 无阴影细线(14) → 分组对齐(15)
→ 多开窄栏无框(16) → 超窄标题栏(17) → 纵向固定四槽(18)
→ 内置加速/静音(19-20) → 单号快速切换(21) → 开关绑定/联动修复(22,28,32)
→ 扫码导入(25) → 三主题配色(26) → 森绿修正(27) → 安全识别(29-30)
→ 热切换/多开/资源加载稳定化(31-32)
```

可见设计决策收敛路径：**细线无阴影 → 线条图标 → 分组筛选 → 三主题**，最终沉淀为当前这套「柔色底 + 细描边 + 线性图标」的体系。当前 SnowKingNative 即 1.0.31/32 的原生重写版。

---

## 七、总结

| 维度 | 评分 | 说明 |
|---|---|---|
| 视觉一致性 | ★★★★☆ | 三主题 token 化彻底，扣分在字符图标/粗描边残留 |
| 图标体系 | ★★★★★ | 33 枚自绘线性图标，风格统一零资源 |
| 信息架构 | ★★★★☆ | 五段式层级清晰，底导航直达多开 |
| 交互规范 | ★★★★☆ | BottomSheet 体系完整，扣分在系统弹窗混用 |
| 工程实现 | ★★★★☆ | 代码构建 UI 维护成本可控，但存在死代码与默认值背离 |
| 无障碍/可用性 | ★★★☆☆ | 多开微栏触摸目标过小、无深色模式 |

**优先修复建议**：① 清理死代码 → ② 字符图标全部替换为 LineIconDrawable → ③ 系统弹窗迁移 BottomSheet → ④ 多开微栏加大触摸热区。这四项完成后，整套 UI 可达到「设计语言完全自洽」的状态。
