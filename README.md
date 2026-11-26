# OpenWrt 校园网共享与防检测部署笔记

> 在 **小米 AC2100（MT7621）** 上跑 OpenWrt，用**无线客户端模式**接入校园网，
> 通过 **锐捷 eportal 自动认证** + **UA3F 的 UA/TTL 改写**，
> 让一个账号稳定供给宿舍多台设备使用，并附一套完整的排错方法。

**这是一个"踩坑记录 + 可复用脚本"仓库，不是一键刷机包。**
所有配置都需要按你所在学校、设备型号做替换。

---

## 这个项目解决什么问题

典型的高校宿舍网络结构是：一个账号、限制接入设备数、网页认证（Portal）、
有线口可能被封、只能用无线。想多台设备共用，会同时撞上四堵墙：

| 墙 | 表现 | 本仓库的解法 |
|---|---|---|
| 认证 | 路由器不会自己弹认证网页 | 逆向 Portal 接口，脚本登录 + 看门狗重连 |
| 接入方式 | 有线口被封，只能用无线 | 5G 射频做 STA 客户端，2.4G 开 AP |
| 共享检测 | 一个账号后面挂多台设备会被识别 | UA3F 统一 User-Agent、固定 TTL |
| 系统坑 | 各种"能上网但游戏/加速器全废" | 逐条记录了根因和修法 |

---

## 两种做法，按自己的情况选

| | [方法 A：AI 辅助版](docs/method-a-ai-assisted.md) | [方法 B：纯手搓版](docs/method-b-hands-on.md) |
|---|---|---|
| 适合谁 | 不想啃原理，想尽快跑通 | 想搞清楚每一步在干什么 |
| 怎么干 | 把需求拆成小段丢给 AI，AI 出命令，你负责执行和验收 | 照着文档一步步敲，理解每个参数 |
| 门槛 | 会复制粘贴、会看报错 | 会 SSH、看得懂 shell |
| 用时 | 半天到一天 | 一到两个晚上 |
| 风险 | AI 会幻觉，必须人工把关危险命令 | 慢，但每一步都可控 |

两条路都要先读 **[排错手册](docs/troubleshooting.md)**——
本仓库一半的价值在里面（18 个真实故障的根因与修法）。

---

## 整体架构

```
        校园 AP（开放 SSID + Portal 认证）
                 ▲
                 │ 5G 客户端模式（STA）
                 │ 关键：钉死 BSSID、钉死 MAC、评估重传率
        ┌────────┴────────┐
        │  小米 AC2100    │  OpenWrt 24.10.x
        │  192.168.1.1    │
        ├─────────────────┤
        │ 2.4G AP         │──→ 宿舍其它设备（NAT 隐藏，不占账号设备数）
        │ 全协议 NAT      │    TCP / UDP / ICMP 都要通
        │ UA3F（REDIRECT）│    HTTP UA 改写 + TTL 固定
        │ Portal 看门狗   │    每 2 分钟自愈
        │ 链路质量监控    │    每分钟采样，记录尖峰
        └─────────────────┘
```

**为什么是"无线客户端 + AP"而不是"有线 WAN"**：
很多学校把宿舍有线口封了，只能连校园 WiFi。此时路由器必须自己扮演一台设备去关联、去认证。

---

## 仓库结构

```
.
├── README.md                      总览（本文件）
├── docs/
│   ├── method-a-ai-assisted.md    方法 A：AI 辅助
│   ├── method-b-hands-on.md       方法 B：纯手搓（含原理）
│   ├── troubleshooting.md         排错手册：18 个真实故障
│   └── credits.md                 致谢与完整出处
├── scripts/
│   ├── portal-login.sh            锐捷 eportal 登录/登出
│   ├── wifi-watchdog.sh           WiFi 链路看门狗
│   ├── ua3f-bypass.sh             让 P2P 端口绕过 UA3F
│   ├── net-monitor.sh             链路质量采样
│   ├── 99-wwan-fw4-reload         wwan 起来后重载防火墙（防 UDP 全丢）
│   └── 99-speed.conf              BBR + 大缓冲区
├── LICENSE
└── .gitignore
```

---

## 三分钟看懂关键结论

如果你只想拿走最值钱的几条：

1. **UA3F 必须用 `REDIRECT` 模式**。`TPROXY` 会把转发流量 tproxy 到 `127.0.0.1:1080`，
   回环地址在转发路径上不成立，客户端直接全断。
2. **上行是 WiFi 客户端时，`fw4` 生成的规则可能只匹配物理网口 `wan`**，
   导致 UDP/ICMP 走 FORWARD 被默认 `drop` —— 表现为"网页正常、所有游戏和加速器全废"。
   排查命令：`nft list ruleset | grep -c <你的STA接口名>`，为 0 就 `fw4 reload`。
3. **UA3F 会终结所有 TCP**，因此 P2P 类软件（游戏启动器、B 站 PCDN）的
   几百条半死连接会把它撑爆（fd 上千、内存耗尽、整机卡死）。要把这些端口/域名绕开。
4. **学校 DNS 常常把你指向远处的 CDN 节点**，网页首字节从 0.07 秒劣化到 2 秒。
   用分流 DNS（公共 DNS 解析常规域名 + 校园 DNS 解析校内域名）可以解决。
5. **别只看信号强度选 AP**。一个 `-23 dBm` 的 AP 可能因为客户端太多，
   重传率高达 43%；看 `tx retries / tx packets` 才准。

---

## 环境与固件

| 项 | 值 |
|---|---|
| 设备 | 小米 AC2100（R2100）/ 红米 AC2100（RM2100），MT7621 + 128MB RAM + 128MB NAND |
| 引导 | Breed r1416（2022-07-24）及以上 |
| 系统 | OpenWrt 24.10.x（`xiaomi_mi-router-ac2100` / `xiaomi_redmi-router-ac2100`） |
| 认证 | 锐捷 eportal（`InterFace.do?method=login`），其它 Portal 需自行适配 |

刷机细节见 [方法 B 第 1 章](docs/method-b-hands-on.md#1-刷机从-breed-到-openwrt)。

---

## 致谢

本仓库大量内容直接受益于下面这些作者与项目，**完整清单与链接见 [docs/credits.md](docs/credits.md)**：

- [SunBK201](https://blog.sunbk201.site/) —— UA2F/UA3F 方案、校园网检测机制研究、OpenWrt 部署教程
- [UA3F](https://github.com/SunBK201/UA3F) —— 本方案的核心组件
- [Zxilly/UA2F](https://github.com/Zxilly/UA2F) —— 前一代方案
- [OpenWrt](https://openwrt.org/) 与 [AC2100 设备页](https://openwrt.org/toh/xiaomi/xiaomi_redmi_router_ac2100)
- [hackpascal/Breed](https://breed.hackpascal.net/) —— 刷机引导
- [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash)、[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo/tree/Meta) —— 若需要代理分流时的可选组件

---

## 免责声明（请务必读完）

> **一、合规风险**
> 多设备共享账号、修改 User-Agent / TTL 以规避检测，通常**违反学校《校园网管理办法》**
> 或《学生上网公约》中"实名认证""禁止共享""禁止代理"等条款。
> 一旦被识别，处置对象是**账号持有人**（断网、封号、纪律处分等）。
> 本项目仅记录技术过程，**不鼓励、不建议**用于违反校规的场景，使用后果自负。
>
> **二、设备风险**
> 刷 Bootloader、写分区存在**变砖**可能。掉电、刷错镜像、用错分区布局都可能救不回来
> （需要拆机接编程器）。请务必先完整备份 flash 与 EEPROM。**操作前确认自己能承担后果。**
>
> **三、可用性**
> 各校 Portal 实现、无线环境、运营商策略差异极大。**本仓库的配置不保证在你的环境可用**，
> 所有 IP、域名、SSID、参数都需要替换成你自己的。
>
> **四、隐私**
> 仓库内所有示例**均为脱敏占位符**。请勿把真实学号、密码、MAC、校内域名提交进公开仓库。
>
> **五、无担保**
> 代码与文档按"现状"提供，不附带任何明示或暗示的担保。作者不对因使用本仓库内容
> 造成的网络中断、设备损坏、账号处罚或其它损失负责。

---

## 许可证

[MIT](LICENSE)
