#!/system/bin/sh
# 点「操作」按钮：暂停 / 恢复 root 通道 + 显示宿主目录桥状态
MODDIR=${0%/*}
P=/sdcard/Download/DSH-Go/rootd-pause
mkdir -p /sdcard/Download/DSH-Go 2>/dev/null
if [ -e "$P" ]; then
  rm -f "$P"
  echo "已恢复：root 命令会继续执行，挂载巡检也会恢复"
else
  : >"$P"
  echo "已暂停：所有 root 命令不再执行，挂载巡检暂停（已有挂载不动）"
fi
if pgrep -f 'dshgo_rootd/service\.sh' >/dev/null 2>&1; then
  echo "守护：运行中"
else
  echo "守护：没在跑（重启手机或重新启用模块）"
fi
. "$MODDIR/config.sh" 2>/dev/null
RFS_D=${RFS:-}
[ -d "$RFS_D" ] || RFS_D=/data/user/0/$PKG/files/runtime/rootfs
cnt=0
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in libproot.so|node|dsh) ;; *) continue ;; esac
  grep -q "$RFS_D" "$d/mountinfo" 2>/dev/null || continue
  pid=${d#/proc/}
  n=$(nsenter -t "$pid" -m -- /system/bin/sh -c "grep -c \" $RFS_D/host/\" /proc/self/mounts 2>/dev/null" 2>/dev/null)
  [ -n "$n" ] && cnt=$n && break
done
echo "宿主目录桥：已挂 ${cnt:-0} 个目录（预期 12）"
