#!/bin/bash
# 一键编译三平台到 release/ 目录
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$PROJECT_DIR/release"

echo "=== 安济桥成 · 导出脚本 ==="

# 清理旧构建
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/linux" "$RELEASE_DIR/windows" "$RELEASE_DIR/macos"

# 导入项目资源
echo "[1/4] 导入项目..."
godot --headless --import --quit --path "$PROJECT_DIR" 2>/dev/null || true

# 导出 Linux
echo "[2/4] 导出 Linux..."
godot --headless --export-release "Linux" "$RELEASE_DIR/linux/game.x86_64" --path "$PROJECT_DIR"

# 导出 Windows
echo "[3/4] 导出 Windows..."
godot --headless --export-release "Windows" "$RELEASE_DIR/windows/game.exe" --path "$PROJECT_DIR"

# 导出 macOS
echo "[4/4] 导出 macOS..."
godot --headless --export-release "macOS" "$RELEASE_DIR/macos/game.zip" --path "$PROJECT_DIR"

echo ""
echo "=== 导出完成 ==="
echo "  Linux:   $RELEASE_DIR/linux/game.x86_64"
echo "  Windows: $RELEASE_DIR/windows/game.exe"
echo "  macOS:   $RELEASE_DIR/macos/game.zip"
