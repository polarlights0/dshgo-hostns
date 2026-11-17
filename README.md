# DSH-Go 宿主目录桥

一个 Magisk 模块：给跑在 proot 容器里的 **dsh-go**（DeepSeek Harness 手机版）开一条「看得见手机 + 能用 root 干活」的通道。

## 解决什么问题

dsh-go 的 Ubuntu 环境是 proot 容器，真实身份只是一个普通 App（`uid=10xxx`、`CapEff=0`）：
看不到 `/data`、`/product`，也没有真正的 root。想在里面直接反编译 APK、读别的 App 数据、调试进程，
就得反复搬文件、反复切身份。

## 它做什么

1. 开机把宿主关键目录 **bind 进容器的 mount namespace**（12 个路径，见下）
2. 把三条命令装进容器的 `/usr/local/bin`
3. 常驻巡检：容器重启会换 mount namespace，自动补挂（20 秒一次，幂等，不叠加）

挂进容器的路径：

```
/host/data/{data,app,adb,local/tmp,system,misc,media}
/host/{product,vendor,system_ext,odm,debug_ramdisk}
```

## 三条命令

| 命令 | 身份 | 视角 |
|---|---|---|
| `root-run '<cmd>'` | 宿主真 root | 宿主路径，一次性执行，护栏最全 |
| `root-ns '<cmd>'` | 容器内真 root（`u:r:magisk:s0`） | 容器 rootfs + `/host/*` + 容器全套工具链 |
| `host-mount` | — | 手动补挂（掉了才需要） |

```bash
root-run 'id'                          # uid=0(root) context=u:r:magisk:s0
root-ns  'ls /host/data/data | head'   # 857 个 App 目录
root-ns  'jadx -d /tmp/out /host/data/app/…/base.apk'
root-ns - <<'EOF'                      # 多行
id; uname -r; ls /host/data/adb/modules
EOF
```

`root-ns` = `root-run` + `nsenter` + `chroot` 的组合糖：命令仍走 rootd 信箱投递，
所以**完整继承** rootd 的 token 校验、120 秒新鲜度、硬拦截（分区/引导/`dd`/`rm -rf /`）、
软拦截（`pm clear`、删相册、递归删 `/data/data`）和审计日志，没有新增绕过路径。

## 安装

1. 下载 Release 里的 `dshgo_rootd-vX.zip`
2. Magisk → 模块 → 从本地安装 → 重启
3. 验证：`root-ns 'id'`、`host-mount`

包名不是 `io.github.ccch1mneyyy.dsh_app` 的话，改 `config.sh` 里的 `PKG` 后重新打包（`bash build.sh`）。

## 文件

```
module.prop      模块元数据
config.sh        PKG / RFS / HOSTDIRS
service.sh       开机守护：信箱循环 + 挂载巡检（单进程）
action.sh        Magisk 「操作」按钮：暂停/恢复 + 桥状态
bin/mounts.sh    挂载逻辑（在目标 ns 内执行，幂等）
bin/bridge.sh    宿主侧桥：找 ns → nsenter → chroot
bin/root-ns      容器命令：真 root 执行
bin/host-mount   容器命令：补挂
bin/root-run     容器命令：rootd 客户端入口
bin/selfcheck.sh 自检 + 干跑（不安装也能跑）
uninstall.sh     卸载：撤挂 + 删容器命令
```

## 边界与注意

- **不提高上限**：普通 uid 依然读不到别的 App 私有数据（0700 + SELinux），必须走 `root-ns`
- **不是提权工具**：root 能力由 rootd 信箱提供，本模块只做「挂载 + 转发 + 巡检」
- 挂载只存在于 dsh-go 容器的 mount namespace，系统里其他 App 看不到
- `HOSTDIRS` 刻意不含 `data`、`data/user`：容器 rootfs 自身在 `/data/user/0/...`，整树 bind 会路径自引用
- 暂停开关 `/sdcard/Download/DSH-Go/rootd-pause` 存在时，命令和挂载巡检都停

## 环境

实测：Android 16（HyperOS 3）+ Magisk 31.1 + 内核 6.1.138，aarch64。
只用 toybox 命令（`grep/sed/awk/cmp/nsenter/chroot/mount/date/pgrep`），不依赖 busybox。

## 许可

MIT
