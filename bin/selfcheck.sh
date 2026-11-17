#!/system/bin/sh
# 自检 / 干跑：不安装、不落盘、不改挂载
MODDIR=${0%/*}; MODDIR=${MODDIR%/*}
. "$MODDIR/config.sh"
fail=0
chk() { if eval "$2"; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

echo "== 1. 模块元数据 =="
for k in id name version versionCode author description; do
  v=$(sed -n "s/^$k=//p" "$MODDIR/module.prop")
  chk "module.prop $k" "[ -n \"\$v\" ]"
done
idv=$(sed -n 's/^id=//p' "$MODDIR/module.prop")
if echo "$idv" | grep -qE '^[a-z0-9_]+$'; then echo "  PASS  id 格式（$idv）"; else echo "  FAIL  id 格式"; fail=$((fail+1)); fi

echo "== 2. 脚本语法 =="
for f in service.sh action.sh uninstall.sh bin/mounts.sh bin/bridge.sh bin/selfcheck.sh bin/root-ns bin/host-mount bin/root-run; do
  chk "sh -n $f" "/system/bin/sh -n '$MODDIR/$f'"
done

echo "== 3. 可执行位 =="
for f in service.sh action.sh uninstall.sh bin/mounts.sh bin/bridge.sh bin/root-ns bin/host-mount bin/root-run; do
  chk "x $f" "[ -x '$MODDIR/$f' ]"
done

echo "== 4. 合并完整性 =="
chk "config.sh 有 HOSTDIRS" "grep -q '^HOSTDIRS=' '$MODDIR/config.sh'"
n=$(echo $HOSTDIRS | tr ' ' '\n' | grep -c .)
chk "HOSTDIRS 条目数=$n" "[ '$n' -ge 10 ]"
chk "service.sh 含 hostns_tick" "grep -q 'hostns_tick()' '$MODDIR/service.sh'"
chk "service.sh 含主循环钩子" "grep -q 'HOSTNS_TICK' '$MODDIR/service.sh'"
chk "service.sh 保留软拦截" "grep -q 'soft_hit' '$MODDIR/service.sh'"
chk "service.sh 保留硬拦截" "grep -q 'hard_hit' '$MODDIR/service.sh'"
chk "容器命令指向本模块路径" "grep -q '/data/adb/modules/dshgo_rootd/bin/bridge.sh' '$MODDIR/bin/root-ns'"

echo "== 5. 运行环境 =="
chk "容器 rootfs 存在" "[ -d '$RFS' ]"
chk "rootd 信箱存在" "[ -d /sdcard/root-requests ] || [ -d '$RFS/root/.dsh/rootd/req' ]"

echo "== 6. 目标 mount ns + 干跑 =="
pid=$(for d in /proc/[0-9]*; do
        c=$(cat "$d/comm" 2>/dev/null) || continue
        case "$c" in libproot.so|node|dsh) ;; *) continue ;; esac
        grep -q "$RFS" "$d/mountinfo" 2>/dev/null && { echo ${d#/proc/}; break; }
      done)
if [ -n "$pid" ]; then
  echo "  样例 pid=$pid ns=$(readlink /proc/$pid/ns/mnt)"
  nsenter -t "$pid" -m -- /system/bin/sh -c "
    for s in $HOSTDIRS; do
      t=$RFS/host/\$s
      if grep -qF \" \$t \" /proc/self/mounts 2>/dev/null; then echo \"  SKIP  /\$s 已挂\"
      elif [ -e \"/\$s\" ]; then echo \"  WOULD /\$s → \$t\"
      else echo \"  MISS  /\$s 不存在\"; fi
    done"
else
  echo "  容器未运行，跳过"
fi
echo
[ "$fail" -eq 0 ] && echo "结论：全部通过 (0 失败)" || echo "结论：$fail 项失败"
exit $fail
