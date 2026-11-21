# 离线围棋

安卓围棋对练应用。APK 内置 KataGo 和模型，首次打开即可离线对弈。支持 9×9、13×13、19×19，黑白选边、三档难度、停一手、悔棋、认输、计分和本地续局。执行 [开发计划](DEVELOPMENT_PLAN.md) 中的 `chinese-ogs` 规则，白贴 7.5 点。

棋盘使用接近屏宽的布局。落子时先点选交叉点，使用棋盘下方的方向键逐格微调，再点「确认落子」。半透明棋子表示当前选点，可随时取消。

## 构建和安装

已使用 Flutter 3.50.1、JDK 17、Android SDK 36、NDK 28.2.13676358 和 CMake 3.22.1 构建。

```sh
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

本地 APK 使用 Android 调试密钥签名，支持 Android 7.0 及以上的 ARM64 设备。首次构建时 CMake 下载并校验固定版本的 KataGo 1.16.5 和 Eigen 3.4.0 源码。模型随仓库和 APK 分发，安装后无需下载任何内容。[KataGo 源码](https://github.com/lightvector/KataGo/tree/v1.16.5) · [Eigen 源码](https://gitlab.com/libeigen/eigen/-/tree/3.4.0)

## 模型与难度

在「新对局」或对弈界面下方的「AI 模型」中选择四个内置模型。默认使用 `b6c96`，局中切换保留棋谱，新模型用于下一手 AI。存档记录当前模型，旧存档默认使用 `b6c96`。

| 模型 | 内置模型文件 | 压缩大小 |
| --- | --- | ---: |
| `b6c96` | `kata1-b6c96-s175395328-d26788732.txt.gz` | 4.97 MB |
| `b10c128` | `kata1-b10c128-s1141046784-d204142634.txt.gz` | 14.47 MB |
| `b15c192` | `kata1-b15c192-s1672170752-d466197061.txt.gz` | 48.04 MB |
| `b20c256x2` | `kata1-b20c256x2-s5303129600-d1228401921.bin.gz` | 87.36 MB |

四个模型都从 g170 导入，适用 CC0 1.0。KataGo 官方评级中，`b20c256x2` 高于表中的 `b15c192`。完整许可随 APK 分发，应用右上角可查看。[官方模型目录](https://katagotraining.org/networks/) · [模型许可](https://katagotraining.org/network_license/)

| 棋盘 | 初级访问上限 / 秒 | 中级访问上限 / 秒 | 高级访问上限 / 秒 |
| --- | ---: | ---: | ---: |
| 9×9 | 10 / 0.7 | 32 / 1.4 | 96 / 2.8 |
| 13×13 | 9 / 0.8 | 26 / 1.6 | 72 / 3.0 |
| 19×19 | 8 / 1.0 | 22 / 2.0 | 60 / 3.5 |

初级和中级按访问次数及与推荐着法的效用差加权选点。高级采用引擎推荐着法。三档仅在引擎推荐停一手时停着。表中的预算是待真机校准的初值。

## 验证记录

在 ARM64 模拟器开启飞行模式后安装并首次启动 APK，分别使用 Android API 37 的 4 KB 环境和 Android API 35 的 16 KB 环境验证。三种棋盘均完成落子和 AI 应答，验证了执白时 AI 先行、难度选择、占点拒绝、悔棋和重开。强制结束进程后，棋盘、执子方、难度、认输结果和连续停一手的计分结果均恢复。

下表是在 4 KB ARM64 模拟器中使用 `b6c96` 的原生引擎样本。冷加载计时从创建引擎到对应尺寸的模型可用。每档测一手，RSS 为原生验证进程截至该尺寸的峰值。

| 棋盘 | 冷加载 | 初级 | 中级 | 高级 | 峰值 RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| 9×9 | 149 ms | 15 ms | 44 ms | 103 ms | 41.5 MiB |
| 13×13 | 133 ms | 27 ms | 50 ms | 122 ms | 44.8 MiB |
| 19×19 | 133 ms | 36 ms | 78 ms | 181 ms | 50.8 MiB |

Android 集成测试覆盖三种尺寸和三档搜索、提子、占点、劫争、禁入、计分、取消搜索、局中切换难度、悔棋、换盘和恢复 AI 回合。四个模型均在飞行模式下通过 19×19 搜索测试。界面验证覆盖开局选模型、局中切换、重启恢复和旧存档读取。

```sh
flutter test integration_test/offline_engine_test.dart -d <device-id>
"$ANDROID_HOME/build-tools/36.0.0/zipalign" -c -P 16 -v 4 build/app/outputs/flutter-apk/app-release.apk
```

APK 通过 16 KB ZIP 对齐检查，三个 ARM64 动态库的 ELF `LOAD` 段对齐均为 16 KB 或更大。[Android 16 KB 检查方法](https://developer.android.com/guide/practices/page-sizes)

真机验收待完成，包括冷启动、单步耗时和峰值内存，长局稳定性，以及三种棋盘上相邻档位交换黑白的多组对弈。
