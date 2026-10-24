# FilmLab iOS 原生版

SwiftUI + Metal + AVFoundation 写的原生 App。胶片引擎是网页版 FilmLab 的 Metal 移植（包括调过的 Velvia 100），相机是原生实时取景，冲印后直接存入相册。

需要：Mac + Xcode 16 或更新版本，iPhone 系统 iOS 17 或更新。

## 第一次装到 iPhone

1. **打开项目**：双击 `FilmLab.xcodeproj`。
2. **选签名团队**：
   - 左侧点最上面蓝色的 **FilmLab** 项目图标 → 中间选 **TARGETS → FilmLab** → 顶部 **Signing & Capabilities**。
   - 勾选 **Automatically manage signing**，**Team** 选你的 "(你的名字) (Personal Team)"。
   - 如果提示 Bundle Identifier 已被占用，把 `com.jche731.filmlab` 改成任意独特的名字，例如 `com.你的名字.filmlab`。
3. **选手机**：用数据线连上 iPhone 并解锁，在 Xcode 顶部中间的设备菜单里选你的 iPhone（不要选模拟器，模拟器没有相机）。
4. **运行**：点左上角 ▶︎（或按 ⌘R）。第一次会编译一两分钟。
5. **第一次在手机上打开**：
   - 如果提示"未受信任的开发者"：iPhone **设置 → 通用 → VPN 与设备管理** → 点你的 Apple ID → **信任**。
   - 如果提示需要开发者模式：**设置 → 隐私与安全性 → 开发者模式** → 打开 → 重启手机。
   - 再点一次 ▶︎ 或直接点手机上的 FilmLab 图标。
6. 允许使用相机和"添加到相册"。

用免费 Apple ID 装的 App 7 天后会失效，到时候连上 Mac 再点一次 ▶︎ 就续上了。付费开发者账号装一次可以用一年。

## 编译报错怎么办

把 Xcode 左侧 ⚠️/⛔️ 面板（Issue navigator，⌘5）里的红色错误截图发给 Claude，改好的文件会再发给你，替换到 `FilmLab` 文件夹里重新 ▶︎ 即可。

## 文件

| 文件 | 内容 |
| --- | --- |
| `Films.swift` | 28 种胶片参数、暗房常量、相框与画幅 |
| `Settings.swift` | 可保存的设置、着色器参数计算 |
| `Shaders.metal` | 胶片引擎：高光提取、模糊（光晕/柔焦）、胶片显影、放大机与相纸、颗粒 |
| `FilmRenderer.swift` | Metal 渲染：实时取景画面与离屏冲印 |
| `CameraController.swift` | 实时取景、对焦、全分辨率拍照 |
| `Compositor.swift` | 35mm/120 底片边、幻灯片框、暗房相纸、拍立得、日期戳 |
| `AppModel.swift` | 状态、预览渲染、冲印、存相册、色环 |
| `ContentView.swift` 等 | 界面：转盘、旋钮、面板、显影动画 |
