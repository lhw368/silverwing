# 星港机甲小队 · 银翼 / Silverwing

Godot 4.7.2 制作的 2D 机甲动作游戏，支持 iOS 横屏触控和桌面键盘。当前源码版本 **0.9.1 / Build 2**，包含三关、银翼与可解锁角色绯刃、机甲驾驶、物资、机关与 Boss 战。

## 运行

安装 Godot 4.7.2，导入 `game/project.godot`，等待资源导入后按 F5。

```sh
godot --path game --editor
godot --path game
```

A/D 或方向键移动，W/↑/Space 跳跃，J 普攻，K 重击，L/Shift 闪避，U 技能，E 或 S/↓ 交互及上下机甲，1/2/3 使用物资，Esc 暂停。F7 切换桌面触控预览；iPhone 自动显示虚拟摇杆和按钮。

## iOS 构建

需要 macOS、Xcode 和与 Godot 4.7.2 匹配的 iOS 导出模板。在 Godot 的 iOS 导出预设中，将占位 Team ID `YOURTEAMID` 替换为自己的团队，将 `org.example.silverwing` 替换为自己拥有的 Bundle ID。

```sh
mkdir -p game/builds/ios
godot --headless --path game --export-release iOS builds/ios/Starport-iOS.xcodeproj
```

打开生成的 Xcode 工程，选择自己的开发团队。Archive 使用 Release。`game/tools/prepare_ios_testflight.py` 可清理未使用权限并同步归档配置；**使用前将脚本的 `BUNDLE_ID` 改为与导出预设一致的自己的标识**。

仓库提供可重新导出的源码和素材，不包含 Apple 私钥、证书、描述文件、预编译引擎或已签名 IPA。TestFlight 上传、Apple 审核及真机验收需要自行完成。

## 自动检查

```sh
python3 tools/check_game.py --godot godot
```

脚本复制到临时工程，并为本次测试创建独立存档目录，避免修改正常游戏存档。四组检查覆盖触控、技能、闪避、三关路径与关卡规则；这些是确定性测试夹具，不等于人工全关通关。

2026-10-23：四组 **288 项通过**；Godot iOS Release 导出及 Xcode Release 未签名编译通过。退出仍有既有资源清理提示，详见 [验证记录](docs/VALIDATION.md)。

## 配套桌面小宠物

[领养银翼桌面宠物](https://chatgpt.com/s/sharepet_6adb581ac1848191a06c39b0251bb72b)，或下载 [宠物原始素材与说明](pets/silverwing/README.md)。原始 v2 精灵图包含九种状态和 16 个视线方向，已通过官方结构验证。领养需要当前账号支持宠物功能；未验证另一账号的安装。游戏角色帧与桌面宠物布局不同，分别保留。

## 目录与许可

- `game/`：Godot 游戏源码、素材、iOS 导出预设和当前回归脚本。
- `tools/`：隔离存档的回归入口。
- `pets/silverwing/`：桌面宠物原始 v2 精灵图、布局清单和官方校验记录。
- `docs/`：开源范围、素材来源与验证记录。

项目自有源码及随附原创生成素材以 [MIT](LICENSE) 许可开放，第三方字体及引擎材料遵循各自许可，见 [素材说明](docs/ASSETS.md) 和 `game/LICENSES/`。
