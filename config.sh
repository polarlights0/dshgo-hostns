# 本模块配置：目标容器 rootfs 位置
PKG=io.github.ccch1mneyyy.dsh_app
RFS=/data/user/0/$PKG/files/runtime/rootfs
# 要挂进容器的宿主目录（相对宿主 /）——不要写 data、data/user，会自引用死循环
HOSTDIRS="data/data data/app data/adb data/local/tmp data/system data/misc data/media product vendor system_ext odm debug_ramdisk"
