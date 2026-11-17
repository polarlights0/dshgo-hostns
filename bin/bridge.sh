#!/system/bin/sh
# 宿主侧桥（由容器里的 root-run 调用）
#   bridge.sh '<mnt:[inode]>'            → 补挂 + 以 root 在 rootfs 内执行 /tmp/.rootns.sh
#   bridge.sh '<mnt:[inode]>' mountonly  → 只补挂
MODDIR=${0%/*}; MODDIR=${MODDIR%/*}
. "$MODDIR/config.sh"
NS="$1"; MODE="${2:-run}"
[ -n "$NS" ] || { echo "用法: bridge.sh '<mnt:[inode]>' [mountonly]" >&2; exit 2; }
PID=""; BEST=""
for p in /proc/[0-9]*; do
  i=${p#/proc/}
  [ "$(readlink "$p/ns/mnt" 2>/dev/null)" = "$NS" ] || continue
  PID=$i
  case "$(cat "$p/comm" 2>/dev/null)" in node|libproot.so) BEST=$i; break;; esac
done
[ -n "$PID" ] || { echo "FAIL: ns $NS 内没有进程（容器没起？）" >&2; exit 1; }
[ -n "$BEST" ] && PID=$BEST
if [ "$MODE" = mountonly ]; then
  out=$(nsenter -t "$PID" -m -- /system/bin/sh "$MODDIR/bin/mounts.sh" 2>&1)
  echo "$out"
  exit 0
fi
nsenter -t "$PID" -m -- /system/bin/sh "$MODDIR/bin/mounts.sh" >/dev/null 2>&1
exec nsenter -t "$PID" -m -- /system/bin/chroot "$RFS" /usr/bin/env -i \
  HOME=/root USER=root LOGNAME=root TERM=xterm TMPDIR=/tmp \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 /bin/bash /tmp/.rootns.sh
