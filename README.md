# 时间悬浮秒表

一个 iOS App，从淘宝 / QQ 音乐服务器校时，悬浮在其他应用上方显示当前时间，专为 巨魔 (TrollStore) 用户准备。

- **画面**：`HH:MM:SS:X`（小时:分:秒:十分之一秒），左上小字标注当前时间源
- **时间源**：本地、淘宝、QQ 音乐三选一，可随时切换并重新校时
- **悬浮窗**：使用 iOS 原生画中画 (PiP)，跨应用悬浮、可拖动、可向边缘"收侧边"
- **签名**：无需付费开发者账号，构建产物已配置为巨魔可直接安装

## 系统要求

- iOS 15.0 或更高（iOS 14 可安装但悬浮窗功能无效，因为系统不支持自定义内容画中画）
- 已安装巨魔 (TrollStore)

---

## 一、把项目放到 GitHub（你只需要做一次）

### 1. 注册 GitHub 账号
打开 https://github.com → Sign up，注册一个免费账号。

### 2. 新建一个空仓库
登录后右上角 `+` → `New repository`：
- **Repository name**：随便起，例如 `TimeFloatingStopwatch`
- **Public** 或 **Private** 都行
- **不要勾** "Add a README"、"Add .gitignore"、"Choose a license"，保持空仓库
- 点 `Create repository`

### 3. 上传本项目文件
你不会用 git 也没关系。在仓库页面，选择 `uploading an existing file`（或者顶栏 `Add file` → `Upload files`）：

需要上传的文件结构（保持目录！）：

```
TimeFloatingStopwatch/
├── project.yml
├── README.md
├── .github/
│   └── workflows/
│       └── build.yml
└── Sources/
    ├── AppDelegate.swift
    ├── ViewController.swift
    ├── StopwatchEngine.swift
    ├── TimeSourceManager.swift
    └── PiPRenderer.swift
```

操作技巧：
1. 把本电脑上 `C:\Users\A\TimeFloatingStopwatch\` 这整个文件夹打开
2. 把里面所有文件 / 子文件夹**一次性拖进** GitHub 的上传区域。GitHub 会自动保留目录结构
3. 注意 `.github` 是隐藏目录，Windows 资源管理器需要在"查看"里勾选"隐藏的项目"才能看到
4. 拖完后下方 `Commit changes` 直接点确定

---

## 二、让 GitHub 自动构建 .ipa

文件上传完成后，GitHub Actions 会**自动开始构建**：

1. 仓库顶栏点 `Actions`
2. 你会看到一个名为 `Build ipa for TrollStore` 的运行，等它跑完（黄色圆圈 → 绿色对勾，大约 3–5 分钟）
3. 如果出现红色叉号，点进去看日志，把报错贴给我

**构建成功后**：点进那次 Run，下拉到底部的 `Artifacts` 区域，下载 `TimeFloatingStopwatch-ipa.zip` 到电脑。解压得到 `TimeFloatingStopwatch.ipa`。

> 之后每次你在 GitHub 上修改文件，CI 都会自动重新构建。也可以在 Actions 页手动点 `Run workflow` 触发。

---

## 三、用巨魔安装

1. 把 `TimeFloatingStopwatch.ipa` 传到 iPhone（微信文件传输助手、AirDrop、QQ、邮箱、网盘都行）
2. iPhone "文件" App 里找到 ipa，长按 → `共享` → 选择 `TrollStore`
3. 在巨魔里点 `Install`
4. 桌面会出现"时间悬浮秒表"图标，打开即可

---

## 四、使用

1. 顶部选择时间源（本地 / 淘宝 / QQ音乐），App 会立刻向服务器请求一次校时
2. 大屏显示当前时间 `HH:MM:SS:X`
3. 点 **启动悬浮窗** → 切到其他 App → 时间窗口悬浮显示
4. 手指拖动可移动；把悬浮窗向左/右边缘划过去，会自动收成侧边小条；再点小条恢复
5. 如果发现时间漂移，回到 App 点 **重新校时**

---

## 五、常见问题

**Q: 构建失败 / Actions 红叉**
A: 把 Actions 里失败步骤的日志截图发我。最常见原因是文件上传时目录结构没保留。

**Q: 装好后图标是问号 / 启动闪退**
A: 巨魔需要 iOS 14+，再检查 iOS 版本和巨魔版本是否匹配。重新打开巨魔 → `TimeFloatingStopwatch` → `Open` 看看具体提示。

**Q: 点了启动悬浮窗没反应 / 提示不支持**
A: 你的 iOS 是 14.x，自定义内容 PiP 需要 iOS 15+。要么升级系统，要么放弃悬浮窗只用 App 内显示。

**Q: 校时失败**
A: 检查网络（淘宝接口是 http，QQ 是 https）。失败时会自动回落本地时间。

**Q: 想改显示样式 / 字体大小 / 增加毫秒位**
A: 改 `Sources/PiPRenderer.swift` 里 `renderPixelBuffer` 函数中的字体大小和 `StopwatchEngine.swift` 里 `formattedTime` 方法即可，push 到 GitHub 会自动重新构建出新版 ipa。

---

## 文件作用

| 文件 | 作用 |
|------|------|
| `project.yml` | xcodegen 项目描述，Actions 据此生成 Xcode 工程 |
| `.github/workflows/build.yml` | GitHub Actions 流水线：编译 + 打包成巨魔可装的 ipa |
| `Sources/AppDelegate.swift` | App 入口 |
| `Sources/ViewController.swift` | 主界面（时间源选择、显示、按钮） |
| `Sources/StopwatchEngine.swift` | 校时偏移管理、格式化输出 |
| `Sources/TimeSourceManager.swift` | 淘宝 / QQ 音乐 HTTP 校时实现 |
| `Sources/PiPRenderer.swift` | 把秒表实时画成视频帧推进画中画 |
