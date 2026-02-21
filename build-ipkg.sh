#!/bin/bash

# luci-app-v2ray 快速编译脚本 - 使用 ipkg-build
# 适配 OpenWrt v24.10+

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION=$(grep "PKG_VERSION:=" Makefile | cut -d'=' -f2)
PKG_NAME=luci-app-v2ray_${VERSION}_all.ipk
BUILD_DIR=build
ARTIFACTS_DIR=artifacts

echo "========================================"
echo "  luci-app-v2ray 快速编译脚本"
echo "  使用 ipkg-build"
echo "  版本: $VERSION"
echo "========================================"
echo ""

cleanup() {
    echo ""
    echo "清理临时文件..."
    rm -rf "$BUILD_DIR"
    echo "完成!"
}

trap cleanup EXIT

echo "1. 创建构建目录..."
rm -rf "$BUILD_DIR" "$ARTIFACTS_DIR"
mkdir -p "$BUILD_DIR/pkg" "$BUILD_DIR/ipkg-build" "$ARTIFACTS_DIR"

echo "2. 准备 ipkg-build 脚本..."
if [ -f "$SCRIPT_DIR/ipkg-build.sh" ]; then
    echo "使用本地 ipkg-build.sh"
    cp "$SCRIPT_DIR/ipkg-build.sh" "$BUILD_DIR/ipkg-build/ipkg-build"
    chmod +x "$BUILD_DIR/ipkg-build/ipkg-build"
else
    echo "错误: 未找到 ipkg-build.sh"
    exit 1
fi

echo "3. 复制项目文件..."
cp -r luasrc "$BUILD_DIR/pkg/"
cp -r root "$BUILD_DIR/pkg/"

echo "4. 创建 CONTROL 目录..."
mkdir -p "$BUILD_DIR/pkg/CONTROL"

cat > "$BUILD_DIR/pkg/CONTROL/control" <<EOF
Package: luci-app-v2ray
Version: $VERSION
Architecture: all
Maintainer: kuoruan
Section: luci
Priority: optional
Title: LuCI support for V2Ray/XRay
Description: Luci support for V2Ray/XRay (v24.10+)
Depends: jshn, luci-lib-jsonc, ip, ipset, iptables, iptables-mod-tproxy, resolveip, dnsmasq-full, luci-compat
EOF

cat > "$BUILD_DIR/pkg/CONTROL/postinst" <<'EOF'
#!/bin/sh

if [ -z "${IPKG_INSTROOT}" ] ; then
	( . /etc/uci-defaults/40_luci-v2ray ) && rm -f /etc/uci-defaults/40_luci-v2ray
fi

chmod 755 "${IPKG_INSTROOT}/etc/init.d/v2ray" >/dev/null 2>&1
ln -sf "../init.d/v2ray" \
	"${IPKG_INSTROOT}/etc/rc.d/S99v2ray" >/dev/null 2>&1

exit 0
EOF
chmod 755 "$BUILD_DIR/pkg/CONTROL/postinst"

cat > "$BUILD_DIR/pkg/CONTROL/prerm" <<'EOF'
#!/bin/sh

if [ -z "${IPKG_INSTROOT}" ] ; then
	/etc/init.d/v2ray stop >/dev/null 2>&1
fi

exit 0
EOF
chmod 755 "$BUILD_DIR/pkg/CONTROL/prerm"

cat > "$BUILD_DIR/pkg/CONTROL/postrm" <<'EOF'
#!/bin/sh

if [ -s "${IPKG_INSTROOT}/etc/rc.d/S99v2ray" ] ; then
	rm -f "${IPKG_INSTROOT}/etc/rc.d/S99v2ray"
fi

if [ -z "${IPKG_INSTROOT}" ] ; then
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
fi

exit 0
EOF
chmod 755 "$BUILD_DIR/pkg/CONTROL/postrm"

echo "5. 设置文件权限..."
chmod 755 "$BUILD_DIR/pkg/etc/init.d/v2ray"
chmod 755 "$BUILD_DIR/pkg/etc/uci-defaults/40_luci-v2ray"

echo "6. 使用 ipkg-build 构建 IPK 包..."
"$BUILD_DIR/ipkg-build/ipkg-build" -o 0 -g 0 "$BUILD_DIR/pkg" "$ARTIFACTS_DIR"

echo ""
echo "========================================"
echo "  编译成功!"
echo "========================================"
echo ""
echo "包文件: $ARTIFACTS_DIR/$PKG_NAME"
if [ -f "$ARTIFACTS_DIR/$PKG_NAME" ]; then
    echo "大小: $(du -h "$ARTIFACTS_DIR/$PKG_NAME" | cut -f1)"
fi
echo ""
echo "安装命令:"
echo "  opkg install $PKG_NAME"
echo ""
ls -la "$ARTIFACTS_DIR/"
