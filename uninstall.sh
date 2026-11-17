#!/system/bin/sh
# 卸载：撤掉所有 bind 挂载 + 删掉装进容器的命令
MODDIR=${0%/*}
. "$MODDIR/config.sh" 2>/dev/null
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in libproot.so|node|dsh) ;; *) continue ;; esac
  grep -q "$RFS" "$d/mountinfo" 2>/dev/null || continue
  pid=${d#/proc/}
  ns=$(readlink "$d/ns/mnt" 2>/dev/null)
  case " $DONE " in *" $ns "*) continue ;; esac
  DONE="$DONE $ns"
  nsenter -t "$pid" -m -- /system/bin/sh -c "
    for s in $HOSTDIRS; do umount \"$RFS/host/\$s\" 2>/dev/null; done
    rmdir \"$RFS/host\"/* 2>/dev/null" 2>/dev/null
done
rm -f "$RFS/usr/local/bin/root-ns" "$RFS/usr/local/bin/host-mount" \
      "$RFS/usr/local/bin/root-run" "$RFS/root/workspace/tools/root-run.py" 2>/dev/null
