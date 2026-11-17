#!/system/bin/sh
# 在目标 mount namespace 内执行：把 HOSTDIRS 逐项 bind 到 $RFS/host/
MODDIR=${0%/*}; MODDIR=${MODDIR%/*}
. "$MODDIR/config.sh"
[ -n "${RFS_OVERRIDE:-}" ] && RFS=$RFS_OVERRIDE
mount --make-rslave / 2>/dev/null
mkdir -p "$RFS/host" 2>/dev/null
n=0
for s in $HOSTDIRS; do
  t=$RFS/host/$s
  mkdir -p "$t" 2>/dev/null
  if grep -qF " $t " /proc/self/mounts 2>/dev/null; then n=$((n+1)); continue; fi
  if mount --bind "/$s" "$t" 2>/dev/null; then n=$((n+1)); fi
done
echo "mounted=$n"
