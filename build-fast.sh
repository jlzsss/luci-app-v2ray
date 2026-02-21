#!/bin/bash

# 快速构建 luci-app-v2ray ipk 包脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUILD_DIR="${SCRIPT_DIR}/build"

VERSION="3.0.0"
RELEASE="1"

echo "开始构建 luci-app-v2ray ipk 包..."

# 清理旧的构建目录
rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# 复制所有文件到构建目录
echo "复制文件..."

# 复制 root 目录
cp -r "${SCRIPT_DIR}/root"/* "${BUILD_DIR}/"

# 复制 luasrc 目录（Lua 源码）
mkdir -p "${BUILD_DIR}/usr/lib/lua/luci"
cp -r "${SCRIPT_DIR}/luasrc"/* "${BUILD_DIR}/usr/lib/lua/luci/" 2>/dev/null || true

# 复制 htdocs 目录（前端文件）
mkdir -p "${BUILD_DIR}/www"
cp -r "${SCRIPT_DIR}/htdocs"/* "${BUILD_DIR}/www/" 2>/dev/null || true

# 复制翻译文件（po/mo 文件）
if [ -d "${SCRIPT_DIR}/po" ]; then
    mkdir -p "${BUILD_DIR}/usr/lib/lua/luci/i18n"
    # 简单的 .po 文件处理（直接复制，OpenWrt 会在安装时处理）
    cp -r "${SCRIPT_DIR}/po" "${BUILD_DIR}/usr/lib/lua/luci/" 2>/dev/null || true
fi

# 创建 CONTROL 目录
mkdir -p "${BUILD_DIR}/CONTROL"

# 创建 control 文件
echo "创建 control 文件..."
cat > "${BUILD_DIR}/CONTROL/control" <<EOF
Package: luci-app-v2ray
Version: ${VERSION}-${RELEASE}
Depends: jshn, ip, ipset, resolveip, dnsmasq-full, kmod-nft-tproxy, kmod-nft-socket, nftables
Source: luci-app-v2ray
Section: luci
Priority: optional
Maintainer: Xingwang Liao <kuoruan@gmail.com>
Architecture: all
Description: LuCI support for V2Ray/Xray
EOF

# 创建 postinst 脚本（来自 Makefile）
echo "创建 postinst 脚本..."
cat > "${BUILD_DIR}/CONTROL/postinst" <<'EOF'
#!/bin/sh

if [ -z "${IPKG_INSTROOT}" ] ; then
	( . /etc/uci-defaults/40_luci-v2ray ) && rm -f /etc/uci-defaults/40_luci-v2ray

	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/

	killall -HUP rpcd 2>/dev/null
fi

chmod 755 "${IPKG_INSTROOT}/etc/init.d/v2ray" >/dev/null 2>&1
ln -sf "../init.d/v2ray" \
	"${IPKG_INSTROOT}/etc/rc.d/S99v2ray" >/dev/null 2>&1

exit 0
EOF

# 创建 postrm 脚本（来自 Makefile）
echo "创建 postrm 脚本..."
cat > "${BUILD_DIR}/CONTROL/postrm" <<'EOF'
#!/bin/sh

if [ -s "${IPKG_INSTROOT}/etc/rc.d/S99v2ray" ] ; then
	rm -f "${IPKG_INSTROOT}/etc/rc.d/S99v2ray"
fi

if [ -z "${IPKG_INSTROOT}" ] ; then
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/
fi

exit 0
EOF

# 创建 prerm 脚本（空）
touch "${BUILD_DIR}/CONTROL/prerm"
chmod 755 "${BUILD_DIR}/CONTROL/prerm"
chmod 755 "${BUILD_DIR}/CONTROL/postinst"
chmod 755 "${BUILD_DIR}/CONTROL/postrm"

# 确保 init.d 脚本可执行
chmod 755 "${BUILD_DIR}/etc/init.d/v2ray"

# 确保所有脚本可执行
find "${BUILD_DIR}" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
find "${BUILD_DIR}" -type f -path "*/etc/init.d/*" -exec chmod 755 {} \; 2>/dev/null || true
find "${BUILD_DIR}" -type f -path "*/etc/uci-defaults/*" -exec chmod 755 {} \; 2>/dev/null || true

# 下载 ipkg-build（如果不存在）
if [ ! -f "${SCRIPT_DIR}/ipkg-build" ]; then
    echo "下载 OpenWrt ipkg-build..."
    wget -q -O "${SCRIPT_DIR}/ipkg-build" https://raw.githubusercontent.com/openwrt/openwrt/openwrt-24.10/scripts/ipkg-build
    chmod +x "${SCRIPT_DIR}/ipkg-build"
fi

# 构建 ipk 包
echo "构建 ipk 包..."
cd "${SCRIPT_DIR}"
"${SCRIPT_DIR}/ipkg-build" "${BUILD_DIR}" "${OUTPUT_DIR}"

# 清理
rm -rf "${BUILD_DIR}"

IPK_FILE=$(ls "${OUTPUT_DIR}"/luci-app-v2ray_*.ipk 2>/dev/null || true)
if [ -n "${IPK_FILE}" ]; then
    echo ""
    echo "✅ 构建成功！"
    echo "IPK 包位置: ${IPK_FILE}"
    echo ""
    ls -lh "${OUTPUT_DIR}"
    echo ""
else
    echo "❌ 构建失败！"
    exit 1
fi
