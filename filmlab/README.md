# FilmLab 胶片暗房

在 iPhone 上用的胶片模拟 App。转动胶片转盘挑胶片，在彩色暗房里像操作放大机一样调色，最后看着照片在显影盘里慢慢浮现。

- **28 种胶片**：Velvia 50 / Velvia 100、Provia、Astia、Pro 400H、Superia、C200、Classic Chrome、Classic Neg.、Nostalgic Neg.、Eterna、Acros；Portra 160/400/800、Ektar、Gold、Ultramax、Kodachrome 64、Ektachrome E100、Tri-X、Aerochrome（红外）；Ilford HP5、Delta 3200；CineStill 800T / 50D；Agfa Vista；Polaroid 600。
- **胶片转盘**：拖动或甩动旋转，每一格都有咔哒声和震动反馈（iOS 18 起支持网页触感），画面随转随变。
- **彩色暗房**：C / M / Y 分色头旋钮、曝光时间旋钮、相纸反差与表面。负片按 RA-4 规律（加 Y 偏蓝），正片按 Ilfochrome 规律（加 Y 偏黄），黑白片换成 Multigrade 反差等级与硒调、棕调、金调、蓝晒调色。
- **试条**：画面分成五档曝光时间，点中最好的一档。
- **色环对照**：九宫格样片，挑最自然的一张直接套用滤光。
- **效果**：颗粒（按胶片 ISO 设定）、红色光晕（CineStill 的 halation）、柔焦、暗角、漏光、灰尘划痕、橙色日期戳。
- **相框**：35mm 底片（齿孔 + 片边字）、120 中画幅、幻灯片框、暗房相纸（锉过的黑边 + 铅笔记录）、拍立得。
- **相机**：实时取景（滤镜实时预览）或从相册选图；按「冲印」进入红色安全灯下的显影动画，最后保存原尺寸照片（最长边 4096 像素）。

## 装到 iPhone

App 是一个网页应用（PWA），放在任意 HTTPS 地址上即可，用 Safari 打开后「分享 → 添加到主屏幕」，之后像普通 App 一样全屏、离线使用。实时取景需要 HTTPS。

最快的方式：

1. 解压 `FilmLab.zip`，得到 `FilmLab` 文件夹。
2. 打开 <https://app.netlify.com/drop>，把文件夹拖进去，几秒后得到一个 https 网址。
3. iPhone 上用 Safari 打开这个网址 → 分享 → 添加到主屏幕。

也可以把 `www/` 里的文件放进一个 GitHub 仓库并开启 GitHub Pages，效果一样。

`FilmLab.html` 是把所有内容打包进一个文件的版本，适合在电脑浏览器里直接双击打开使用（这种方式没有离线缓存和主屏幕图标）。

## 文件

| 路径 | 内容 |
| --- | --- |
| `src/app.html` | App 全部源码：界面、WebGL 胶片引擎、转盘、暗房、相框 |
| `assets/` | 样张照片与 App 图标 |
| `build.py` | 生成 `www/`、`FilmLab.html` 和 `FilmLab.zip` |
| `www/` | 可直接部署的 PWA（index.html、manifest、service worker、图标） |

修改 `src/app.html` 后运行 `python3 build.py` 重新生成。

## 原理

每张照片走一条 WebGL 管线：线性光里先加上曝光、红色光晕和柔焦，再按胶片的白平衡、染料串色、分通道 CDL 曲线、S 形反差曲线、六色相饱和度与分离色调显影；然后进入放大机阶段，按 C/M/Y 滤光与曝光时间计算每个通道的相纸曝光，经过相纸反差曲线、调色和相纸白度；最后叠加漏光、灰尘和随 ISO 变化的颗粒。相框、片边字和日期戳在 Canvas 上合成。

胶片效果是对色彩风格的模拟，与各胶片厂商没有关联。样张来自 scikit-image 示例数据：NASA 与 SpaceX（公有领域），Rachel Michetti 与 Stefan van der Walt（CC0）。
