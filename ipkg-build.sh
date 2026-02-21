#!/bin/bash

# 简易 ipkg-build 实现
# 基于 OpenWrt 的 ipkg-build 脚本简化版

set -e

usage() {
    echo "Usage: $0 [-o <owner>] [-g <group>] <pkg_dir> <dest_dir>"
    echo "  -o <owner>  Set owner for files in package"
    echo "  -g <group>  Set group for files in package"
    exit 1
}

OWNER=0
GROUP=0

while getopts "o:g:" opt; do
    case $opt in
        o) OWNER="$OPTARG" ;;
        g) GROUP="$OPTARG" ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

if [ $# -ne 2 ]; then
    usage
fi

# 转换为绝对路径
PKG_DIR="$(cd "$1" && pwd)"
DEST_DIR="$(cd "$2" && pwd)"

if [ ! -d "$PKG_DIR" ]; then
    echo "Error: Package directory $PKG_DIR does not exist"
    exit 1
fi

if [ ! -d "$PKG_DIR/CONTROL" ]; then
    echo "Error: CONTROL directory not found in $PKG_DIR"
    exit 1
fi

if [ ! -f "$PKG_DIR/CONTROL/control" ]; then
    echo "Error: control file not found in CONTROL directory"
    exit 1
fi

# 读取包信息
PACKAGE=$(grep "^Package:" "$PKG_DIR/CONTROL/control" | cut -d' ' -f2)
VERSION=$(grep "^Version:" "$PKG_DIR/CONTROL/control" | cut -d' ' -f2)
ARCH=$(grep "^Architecture:" "$PKG_DIR/CONTROL/control" | cut -d' ' -f2)

if [ -z "$PACKAGE" ] || [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "Error: Failed to parse control file"
    exit 1
fi

PKG_NAME="${PACKAGE}_${VERSION}_${ARCH}.ipk"
TMP_DIR=$(mktemp -d)

echo "Building $PKG_NAME..."
echo "Package dir: $PKG_DIR"
echo "Control dir: $PKG_DIR/CONTROL"

# 创建临时目录
mkdir -p "$TMP_DIR"

# 步骤1: 创建 data.tar.gz（不包含 CONTROL 目录）
cd "$PKG_DIR"
find . -type f -o -type l | grep -v "^./CONTROL" | sort > "$TMP_DIR/files.list"
tar -czf "$TMP_DIR/data.tar.gz" -T "$TMP_DIR/files.list" --owner="$OWNER" --group="$GROUP" 2>/dev/null || tar -czf "$TMP_DIR/data.tar.gz" -T "$TMP_DIR/files.list"

# 步骤2: 创建 control.tar.gz（只包含 CONTROL 目录）
if [ ! -d "$PKG_DIR/CONTROL" ]; then
    echo "Error: CONTROL directory not found at $PKG_DIR/CONTROL"
    exit 1
fi

cd "$PKG_DIR/CONTROL"
find . -type f | sort > "$TMP_DIR/control.files"
tar -czf "$TMP_DIR/control.tar.gz" -T "$TMP_DIR/control.files" --owner="$OWNER" --group="$GROUP" 2>/dev/null || tar -czf "$TMP_DIR/control.tar.gz" -T "$TMP_DIR/control.files"

# 步骤3: 创建 debian-binary
echo "2.0" > "$TMP_DIR/debian-binary"

# 步骤4: 创建最终的 IPK 包
mkdir -p "$DEST_DIR"
cd "$TMP_DIR"
tar -czf "$DEST_DIR/$PKG_NAME" debian-binary control.tar.gz data.tar.gz

echo "Successfully created: $DEST_DIR/$PKG_NAME"

# 清理
rm -rf "$TMP_DIR"
