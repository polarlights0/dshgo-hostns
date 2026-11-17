#!/system/bin/sh
# dsh-go 真 root 信箱守护 v4.3（2026-11-11）
# 私有信箱 + 自适应路径 + 暂停开关 + 不可逆命令拦截 + 新鲜度 + 审计
# 请求：<BASE>/req/<id>.sh    结果：<BASE>/res/<id>.out
# 暂停：/sdcard/Download/DSH-Go/rootd-pause 存在时一条都不执行
# 换手机/换包名：固定路径找不到会通配，再不行每 30 秒 find 一次

MODDIR=${0%/*}
[ -d "$MODDIR/bin" ] || MODDIR=/data/adb/modules/dshgo_rootd
PAUSE=/sdcard/Download/DSH-Go/rootd-pause
ALLOW_DANGER=/sdcard/Download/DSH-Go/rootd-allow-danger
VER=$(grep -m1 '^version=' /data/adb/modules/dshgo_rootd/module.prop 2>/dev/null | cut -d= -f2)
[ -n "$VER" ] || VER=unknown
TMO=120
MAX_AGE=120
BASE=""
REQ=""
RES=""
LOG=""
i=0
start_logged=0
paused_logged=0
client_ok=0

log() {
  [ -n "$LOG" ] || return 0
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null
}

# 开机标记：/data/local/tmp 比 App 数据目录更早就绪
date '+%F %T' >/data/local/tmp/dshgo-rootd.boot 2>/dev/null

# 精确探测：固定包名（每秒一次，开销小）
probe_exact() {
  for c in \
    /proc/1/root/data/user/0/io.github.ccch1mneyyy.dsh_app/files/runtime/rootfs/root/.dsh/rootd \
    /data/user/0/io.github.ccch1mneyyy.dsh_app/files/runtime/rootfs/root/.dsh/rootd; do
    [ -d "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# 通配探测：包名不同但布局相同（每 10 秒一次）
probe_glob() {
  for c in \
    /proc/1/root/data/user/0/*/files/runtime/rootfs/root/.dsh/rootd \
    /data/user/0/*/files/runtime/rootfs/root/.dsh/rootd; do
    [ -d "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# 深度探测：目录布局变了也能找（最多 8 层）
probe_deep() {
  d=$(find /proc/1/root/data/user/0 -maxdepth 8 -type d -path '*/.dsh/rootd' 2>/dev/null | head -n1)
  [ -n "$d" ] && printf '%s' "$d"
}

use_base() {
  BASE=$1
  REQ=$BASE/req
  RES=$BASE/res
  LOG=$BASE/rootd.log
  # 清理上一次的残留
  rm -f "$REQ"/.run-*.sh 2>/dev/null
  find "$RES" -maxdepth 1 -name '*.out' -mmin +1440 -delete 2>/dev/null
  find "$REQ" -maxdepth 1 -name '*.sh' -mmin +60 -delete 2>/dev/null
  if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    tail -n 400 "$LOG" >"$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
}

# ---- 自安装客户端 ----
# 把 root-run.py 放进 App 的 workspace；已存在就不动
detect_rootfs() {
  for c in \
    /proc/1/root/data/user/0/io.github.ccch1mneyyy.dsh_app/files/runtime/rootfs \
    /proc/1/root/data/user/0/*/files/runtime/rootfs; do
    [ -d "$c" ] || continue
    # 只认 dsh-go 的 rootfs：必须带 /etc/dsh-app 或 /root/.dsh
    [ -d "$c/etc/dsh-app" ] || [ -d "$c/root/.dsh" ] || continue
    printf '%s' "$c"; return 0
  done
  return 1
}

install_client() {
  rf=${1:-$(detect_rootfs)}
  [ -n "$rf" ] || return 1
  [ -d "$rf/etc/dsh-app" ] || [ -d "$rf/root/.dsh" ] || return 1
  [ -d "$rf/root/workspace" ] || return 1
  u=$(stat -c %u "$rf/root" 2>/dev/null)
  g=$(stat -c %g "$rf/root" 2>/dev/null)
  t="$rf/root/workspace/tools/root-run.py"
  mkdir -p "$rf/root/workspace/tools" 2>/dev/null || return 1
  if true; then
  cat >"$t.new" <<'CLIENTEOF'
#!/usr/bin/env python3
"""走 App 私有信箱给真 root 守护投命令。

用法:
  python3 tools/root-run.py '命令' [--timeout 60] [--yes]

--yes 只在命令被软拦截（会动相册/存储/别的 App 数据）需要确认时使用。

退出码 = 远端命令的退出码（远端被 timeout 杀掉则是 124）。
"""
import os
import sys
import time
import uuid

BASE = os.path.expanduser("~/.dsh/rootd")
REQ, RES = os.path.join(BASE, "req"), os.path.join(BASE, "res")
PAUSE = "/sdcard/Download/DSH-Go/rootd-pause"


def main():
    args = sys.argv[1:]
    yes = "--yes" in args
    if yes:
        args.remove("--yes")
    tmo = 60.0
    if "--timeout" in args:
        i = args.index("--timeout")
        try:
            tmo = float(args[i + 1])
        except (IndexError, ValueError):
            sys.exit("--timeout 需要秒数")
        del args[i:i + 2]

    cmd = " ".join(args).strip()
    if not cmd:
        sys.exit("用法: python3 tools/root-run.py '命令' [--timeout 秒]")

    if os.path.exists(PAUSE):
        sys.exit(f"[rootd] 通道已暂停（{PAUSE} 存在）。要恢复：删掉这个文件。")

    os.makedirs(REQ, exist_ok=True)
    os.makedirs(RES, exist_ok=True)

    n = "r" + uuid.uuid4().hex[:12]
    req, res = os.path.join(REQ, n + ".sh"), os.path.join(RES, n + ".out")

    tmp = req + ".tmp"
    body = cmd.rstrip("\n") + "\n"
    if yes:
        body = "# approved\n" + body
    with open(tmp, "w") as f:
        f.write(body)
    os.replace(tmp, req)          # 原子落盘，守护不会读到半个文件

    end = time.time() + tmo
    try:
        while time.time() < end:
            if os.path.exists(res):
                with open(res, errors="replace") as f:
                    data = f.read()
                print(data.rstrip())
                code = 0
                for line in data.splitlines():
                    if line.startswith("== exit="):
                        try:
                            code = int(line[len("== exit="):].strip()) & 0xFF
                        except ValueError:
                            pass
                if code == 124:
                    print("[rootd] 远端超时被终止", file=sys.stderr)
                if code == 128:
                    print("[rootd] 需要确认：这条只动用户数据，没执行；确认后加 --yes 重跑。", file=sys.stderr)
                return code
            time.sleep(0.2)
        print(f"[rootd] 超时 {tmo:g}s 没结果（{n}）。守护在跑吗？"
              "可试: su -c 'sh /data/adb/service.d/rootd.sh &'", file=sys.stderr)
        return 124
    finally:
        for p in (tmp, req, res):
            try:
                os.remove(p)
            except OSError:
                pass


if __name__ == "__main__":
    sys.exit(main())
CLIENTEOF
    if [ -f "$t" ] && cmp -s "$t.new" "$t"; then
      rm -f "$t.new"
    else
      mv "$t.new" "$t"
      chmod 755 "$t"
      [ -n "$u" ] && [ -n "$g" ] && chown "$u:$g" "$t" 2>/dev/null
      log "client installed at $t"
    fi
  fi

  d="$rf/root/.dsh/rootd"
  if [ ! -d "$d/req" ] || [ ! -d "$d/res" ]; then
    mkdir -p "$d/req" "$d/res" 2>/dev/null
    [ -n "$u" ] && [ -n "$g" ] && chown "$u:$g" "$d" "$d/req" "$d/res" 2>/dev/null
    log "mailbox created at $d"
  fi
  client_ok=1
  return 0
}
# ---- 拦截规则 ----
# 破坏性动作：递归删除、移动、find 删除/执行
destructive() {
  printf '%s' "$1" | grep -Eq '(^|[[:space:]])rm([[:space:]]|$)' && \
    printf '%s' "$1" | grep -Eq '(^|[[:space:]])-[[:alnum:]-]*[rR][[:alnum:]-]*([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -Eq '(^|[[:space:]])mv([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -Eq '(^|[[:space:]])find([[:space:]]|$)' && \
    printf '%s' "$1" | grep -Eq '(^|[[:space:]])-(delete|exec|execdir|ok|okdir)([[:space:]]|$)' && return 0
  return 1
}

# 硬拦截：分区、引导、系统、root 管理器 —— 不询问，直接拒
hard_hit() {
  printf '%s' "$1" | grep -Eq 'mkfs|mke2fs|fastboot|setenforce[[:space:]]+0' && return 0
  printf '%s' "$1" | grep -Eq 'dd[[:space:]]+[^|]*(if|of)=' && return 0
  printf '%s' "$1" | grep -Eq '>>?[[:space:]]*/dev/block' && return 0
  if destructive "$1"; then
    printf '%s' "$1" | grep -Eq \
      -e '(^|[[:space:]])/([[:space:]]|$)' \
      -e '(^|[[:space:]])/\*([[:space:]]|$)' \
      -e '(^|[[:space:]])/(system|vendor|product|apex|odm)(/|[[:space:]]|$)' \
      -e '(^|[[:space:]])/data([[:space:]]|$|/\*)' \
      -e '(^|[[:space:]])/data/(adb|system|app)(/|[[:space:]]|$)' && return 0
  fi
  return 1
}

# 软拦截：用户数据（相册、存储、别的 App 数据）—— 返回 128，确认后可放行
soft_hit() {
  printf '%s' "$1" | grep -Eq 'pm[[:space:]]+clear' && return 0
  if printf '%s' "$1" | grep -Eq '(^|[[:space:]])rm([[:space:]]|$)'; then
    printf '%s' "$1" | grep -Eq '(^|[[:space:]])/(sdcard|storage/emulated/0)/(DCIM|Pictures|Movies)(/|[[:space:]]|$)' && return 0
  fi
  if destructive "$1"; then
    printf '%s' "$1" | grep -Eq \
      -e '(^|[[:space:]])/(sdcard|storage|storage/emulated/0)([[:space:]]|$|/\*)' \
      -e '(^|[[:space:]])/(sdcard|storage/emulated/0)/(DCIM|Pictures|Movies|Android)(/|[[:space:]]|$)' \
      -e '(^|[[:space:]])/data/data(/|[[:space:]]|$)' && return 0
  fi
  return 1
}

# ---- 宿主目录桥（hostns，v5.0.0 合并）----
# 把宿主关键目录 bind 进 dsh-go 容器的 mount namespace；
# 容器侧命令：root-ns（真 root + 容器工具链）/ host-mount（手动补挂）
HOSTNS_TICK=20
HOSTNS_LAST=0
HOSTNS_INSTALLED=0
RFS=""

hostns_install() {
  rf=$1; [ -n "$rf" ] || return 1
  [ -d "$rf/usr/local/bin" ] || mkdir -p "$rf/usr/local/bin" 2>/dev/null
  u=$(stat -c %u "$rf/root" 2>/dev/null)
  g=$(stat -c %g "$rf/root" 2>/dev/null)
  n=0
  for h in root-run root-ns host-mount; do
    src=$MODDIR/bin/$h; dst=$rf/usr/local/bin/$h
    [ -f "$src" ] || continue
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
    if cp -f "$src" "$dst" 2>/dev/null; then
      chmod 755 "$dst" 2>/dev/null
      [ -n "$u" ] && [ -n "$g" ] && chown "$u:$g" "$dst" 2>/dev/null
      n=$((n+1))
    fi
  done
  [ "$n" -gt 0 ] && { log "hostns install helpers n=$n"; HOSTNS_INSTALLED=1; }
  return 0
}

# 只认容器进程，输出 "ns pid" 并去重（每 ns 一个代表 pid）
hostns_targets() {
  for p in /proc/[0-9]*; do
    c=$(cat "$p/comm" 2>/dev/null) || continue
    case "$c" in libproot.so|node|dsh) ;; *) continue ;; esac
    grep -q "$RFS" "$p/mountinfo" 2>/dev/null || continue
    printf '%s %s\n' "$(readlink "$p/ns/mnt" 2>/dev/null)" "${p#/proc/}"
  done | awk 'NF==2 && !seen[$1]++'
}

hostns_tick() {
  [ -e "$PAUSE" ] && return 0
  if [ -z "$RFS" ] || [ ! -d "$RFS" ]; then
    RFS=$(detect_rootfs 2>/dev/null)
    [ -n "$RFS" ] || return 0
    log "hostns rfs=$RFS"
  fi
  [ "$HOSTNS_INSTALLED" = 1 ] || hostns_install "$RFS"
  tg=$(hostns_targets 2>/dev/null)
  [ -n "$tg" ] || return 0
  sig=""
  echo "$tg" | while read -r ns pid; do
    [ -n "$pid" ] || continue
    out=$(RFS_OVERRIDE="$RFS" nsenter -t "$pid" -m -- /system/bin/sh "$MODDIR/bin/mounts.sh" 2>/dev/null)
    case "$out" in
      mounted=*) printf '%s %s\n' "$ns" "$out" >>"$MODDIR/hostns.sig.tmp" ;;
    esac
  done
  if [ -f "$MODDIR/hostns.sig.tmp" ]; then
    new=$(sort "$MODDIR/hostns.sig.tmp" 2>/dev/null)
    rm -f "$MODDIR/hostns.sig.tmp"
    if [ "$new" != "$(cat "$MODDIR/hostns.sig" 2>/dev/null)" ]; then
      printf '%s\n' "$new" >"$MODDIR/hostns.sig" 2>/dev/null
      log "hostns apply: $(printf '%s' "$new" | tr '\n' ' ')"
    fi
  fi
}

# ---- 主循环 ----
RFS=$(detect_rootfs 2>/dev/null)
[ -n "$RFS" ] && hostns_install "$RFS"
hostns_tick

install_client

while true; do
  _n=$(date +%s 2>/dev/null || echo 0)
  if [ $((_n - HOSTNS_LAST)) -ge $HOSTNS_TICK ]; then
    HOSTNS_LAST=$_n
    hostns_tick
  fi
  i=$((i + 1))
  [ $((i % 30)) -eq 0 ] && install_client
  # 路径自适应：精确路径每秒试，通配每 10 秒，深度探测每 5 分钟
  if [ -z "$BASE" ] || [ ! -d "$BASE" ]; then
    b=$(probe_exact)
    if [ -z "$b" ] && [ $((i % 10)) -eq 0 ]; then
      b=$(probe_glob)
    fi
    if [ -z "$b" ] && [ $((i % 300)) -eq 0 ]; then
      b=$(probe_deep)
    fi
    if [ -n "$b" ]; then
      use_base "$b"
      log "base=$BASE"
    fi
  fi

  if [ -n "$BASE" ] && [ "$start_logged" = 0 ]; then
    log "start pid=$$ base=$BASE $VER"
    start_logged=1
  fi

  if [ -e "$PAUSE" ]; then
    if [ "$paused_logged" = 0 ]; then log "paused by $PAUSE"; paused_logged=1; fi
    sleep 2
    continue
  fi
  if [ "$paused_logged" = 1 ]; then log "resumed"; paused_logged=0; fi

  if [ -n "$BASE" ] && [ -d "$REQ" ]; then
    now=$(date +%s)
    for f in "$REQ"/*.sh; do
      [ -e "$f" ] || continue
      n=$(basename "$f" .sh)

      # 过期请求不执行：防止“趁守护不在时先塞进去，以后开机再跑”
      mt=$(stat -c %Y "$f" 2>/dev/null)
      if [ -n "$mt" ] && [ $((now - mt)) -gt "$MAX_AGE" ]; then
        printf '== %s stale\n请求超过 %ss 未执行，已丢弃\n== exit=125\n' "$(date '+%F %T')" "$MAX_AGE" >"$RES/$n.out"
        rm -f "$f"
        log "stale $n"
        continue
      fi

      mv "$f" "$REQ/.run-$n.sh" 2>/dev/null || continue
      # 拦截检查用全文；日志只留前 300 字节，避免刷屏
      cmd=$(cat "$REQ/.run-$n.sh" 2>/dev/null)
      short=$(printf '%s' "$cmd" | head -c 300 | tr '\n' ' ')
      s=$(printf '%s' "$cmd" | tr '\n' ' ' | tr -d '"' | tr -d "'")
      approved=0
      [ "$(head -1 "$REQ/.run-$n.sh" 2>/dev/null)" = "# approved" ] && approved=1

      if [ ! -e "$ALLOW_DANGER" ]; then
        if hard_hit "$s"; then
          printf '== %s denied\n命令命中硬拦截（分区/引导/系统/root 管理器），没有执行，也不能确认放行。\n确实要跑：在 /sdcard/Download/DSH-Go/ 建 rootd-allow-danger 空文件。\n== exit=126\n' "$(date '+%F %T')" >"$RES/$n.out"
          rm -f "$REQ/.run-$n.sh"
          log "deny-hard $n: $short"
          continue
        fi
        if [ "$approved" != 1 ] && soft_hit "$s"; then
          printf '== %s need-confirm\n这条命令会动用户数据（相册/存储/别的 App 数据），没有执行。\n确认后加 --yes 重跑：python3 tools/root-run.py --yes 命令\n== exit=128\n' "$(date '+%F %T')" >"$RES/$n.out"
          rm -f "$REQ/.run-$n.sh"
          log "ask $n: $short"
          continue
        fi
      fi

      log "run $n: $short"
      if command -v timeout >/dev/null 2>&1; then
        {
          echo "== $(date '+%F %T') uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null)"
          timeout "$TMO" /system/bin/sh "$REQ/.run-$n.sh" 2>&1
          echo "== exit=$?"
        } >"$RES/.$n.tmp" 2>&1
      else
        {
          echo "== $(date '+%F %T') uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null)"
          /system/bin/sh "$REQ/.run-$n.sh" >"$RES/.$n.body" 2>&1 &
          p=$!
          ( sleep "$TMO"; kill -TERM "$p" 2>/dev/null; sleep 2; kill -KILL "$p" 2>/dev/null ) >/dev/null 2>&1 &
          w=$!
          wait "$p"; rc=$?
          kill "$w" 2>/dev/null
          cat "$RES/.$n.body"
          echo "== exit=$rc"
        } >"$RES/.$n.tmp" 2>&1
      fi

      mv "$RES/.$n.tmp" "$RES/$n.out"
      rm -f "$REQ/.run-$n.sh" "$RES/.$n.body"
      log "done $n"
    done
  fi
  sleep 1
done
