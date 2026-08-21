# Atoll 2.3.3 扩展兼容启动项

Atoll 2.3.3 已实现 `com.ebullioscopic.Atoll.xpc`，但当前发行包没有通过 launchd `MachServices` job 启动该监听器。这个 LaunchAgent 只改变 Atoll 的启动方式，不修改 Atoll 应用本体。

## 安装前

1. 在 Atoll → 设置 → 通用中关闭“登录时启动”。
2. 退出 Atoll 和 Codex 额度岛。
3. 将本说明与 `com.dinglicheng.AtollLiveActivityHost.plist` 放在同一个目录。

## 安装

在终端进入文件所在目录后执行：

```sh
mkdir -p "$HOME/Library/LaunchAgents"
cp com.dinglicheng.AtollLiveActivityHost.plist "$HOME/Library/LaunchAgents/"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.dinglicheng.AtollLiveActivityHost.plist"
```

然后启动 `CodexQuotaIsland.app`。Atoll 会由这个 job 启动，“Codex 额度”翻页卡片将自动恢复。

## 卸载

```sh
launchctl bootout "gui/$(id -u)/com.dinglicheng.AtollLiveActivityHost"
rm "$HOME/Library/LaunchAgents/com.dinglicheng.AtollLiveActivityHost.plist"
```

卸载后可以重新打开 Atoll 的“登录时启动”。
