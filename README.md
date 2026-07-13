# NekoBenchmark
<img width="985" height="592" alt="dda2e6134e2336592c3a94588c80d2a1" src="https://github.com/user-attachments/assets/40dd8c15-b741-46dc-a0e6-90f36db4f7d9" />

一个本地运行的基于 SDL3 反应速度测试工具，支持 Windows、Linux 和 macOS。

## 使用

从 GitHub Releases 下载与你的系统对应的压缩包，解压后直接运行其中的可执行文件。
压缩包中的 `MapleMono-Regular.ttf` 与 `NotoSansCJKsc-Regular.otf` 必须与可执行文件放在同一目录。

- `Z`、`X`、`Space`、方向键或鼠标左键：开始测试，以及在目标颜色出现后记录反应。
- 长按任一有效键至少 1 秒后松开：松开时也会作为一次输入触发；下一次测试须再次按键开始。
- `C`：切换红→绿与黄→蓝配色。
- `V`：调换当前配色的起始与目标颜色顺序。
- `L`：切换界面英文与中文文本。
- `Esc`：退出。

每轮会连续测量 5 次。每次会随机等待 1–4 秒后显示目标颜色；颜色显示后超过 1 秒未输入会判为 timeout。false start 或 timeout 会作废整轮，已记录的样本会清空，必须从第 1 次重新开始。

完成 5 次后，结果会显示中位数、平均值和样本标准差。

## 界面

界面英文使用 Maple Mono、中文使用 Noto Sans CJK SC；结果页突出显示中位数，并将平均值、标准差和显示刷新率误差分栏展示。字体在首次使用时缓存为纹理，因此不会在每个渲染帧重复栅格化。

Maple Mono 与 Noto Sans CJK 均以 SIL Open Font License 1.1 随发布包分发。

## 精度与延迟

### 已采取的措施

- 通过 SDL 请求禁用 VSync，以减少 `SDL_RenderPresent` 主动等待垂直同步造成的延迟。
- 目标色切换仅改变纯色背景；其余界面文本会缓存为纹理，避免在测量期间重复进行字体栅格化。
- 反应时间采用 SDL 的纳秒输入事件时间戳，而不是主循环发现事件的时间，避免将事件队列等待时间计入成绩。
- 使用单独的目标颜色状态；输入后的下一次测试立即安排，避免额外的确认点击。

### 结果中会显示的误差

- 程序读取当前显示器报告的刷新率，计算一个帧周期，并将其作为 `FRAME UNCERTAINTY` 显示。例如 60 Hz 的一帧约为 16.67 ms。这反映目标颜色可能在刷新周期中任意时刻开始扫描的时间不确定性。
- SDL 返回的 VSync 状态会显示在窗口中。请求禁用 VSync 不等于操作系统一定允许 immediate present，因此状态仅说明 SDL 渲染器的实际设置。
- 输入设备轮询率明确标为 `NOT MEASURED`；程序不会根据事件间隔猜测它，以免把操作系统调度误差误报为设备能力。

### 软件无法可靠计算的延迟

- 显示合成器、驱动和显示器可能仍会同步或缓冲帧，即使 SDL 已禁用 VSync。
- 显示器扫描方向、像素响应时间与过冲。
- USB 或无线输入设备的固件、轮询率和传输延迟。
- 操作系统输入处理、线程调度及事件队列延迟。

因此该工具适合在相同设备与相同显示配置上做可重复的个人对比，而不是作为跨设备绝对反应时间的校准仪器。

## 本地构建

需要 CMake 3.21+、C++20 编译器和网络连接（首次配置会下载 SDL3）。

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release
```

在单配置生成器（Ninja、Unix Makefiles）中，程序位于 `build/nekobenchmark`；在 Visual Studio/Xcode 中通常位于 `build/Release/nekobenchmark`。

## 许可证

[MIT](LICENSE)
