#!/usr/bin/env bash
# Пересобирает все сборки и кладёт архивы в build/release/ (в git не попадают).
# Готовые архивы выкладываются на страницу Releases на GitHub, см. README.
# Нужны Godot 4.3 и шаблоны экспорта 4.3 (Editor → Manage Export Templates).
#   GODOT=/путь/к/godot tools/export_all.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

mkdir -p build/windows build/macos build/linux build/web build/release
touch build/.gdignore

"$GODOT" --headless --path . --import || true
"$GODOT" --headless --path . --export-release "Windows" build/windows/ZombieCoopFPS.exe
"$GODOT" --headless --path . --export-release "macOS"   build/macos/ZombieCoopFPS.zip
"$GODOT" --headless --path . --export-release "Linux"   build/linux/ZombieCoopFPS.x86_64
"$GODOT" --headless --path . --export-release "Web"     build/web/index.html

cp build/macos/ZombieCoopFPS.zip build/release/ZombieCoopFPS-macOS.zip
(cd build/windows && zip -9 -q -FS ../release/ZombieCoopFPS-Windows-x64.zip ZombieCoopFPS.exe)
(cd build/linux && tar -czf ../release/ZombieCoopFPS-Linux-x64.tar.gz ZombieCoopFPS.x86_64)
(cd build/web && zip -9 -q -r -FS ../release/ZombieCoopFPS-Web.zip .)
ls -la build/release
