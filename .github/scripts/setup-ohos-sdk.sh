#!/usr/bin/env bash
# 在 CI 上准备 OpenHarmony SDK（公开下载，无需华为账号登录）
#
# 用途：为 ArkTS/ArkUI 代码做**编译校验**；正式 HarmonyOS 包仍由 default product 产出。
# 依据：家族 findings §7（CI 构建 HAP 可行性）+ §14（构建一律走 GitHub Actions）
#
# 设计要点（都是被 3.2GB 体积和 runner 磁盘逼出来的）：
#   1. 五个组件全都要解压（少一个 hvigor 就报 "Unable to find the following components"）
#   2. 下载完 tar 立即删除、每个组件解压完立即删 zip、中间目录用完即删（否则磁盘不够）
#   3. 第二套兼容布局用**符号链接**，避免缓存体积翻倍
set -euo pipefail

VER="${1:-6.0.0.2-Release}"
# 第二参数 = 落到哪个目录。兼容性编译会同时用另一套 SDK（例如 API 15），
# 两套必须分目录，否则缓存互相覆盖。
ROOT="${2:-${PWD}/.ohos-sdk}"
# 注意：hvigor 会校验 compileSdkVersion 对应的全部组件，即使本项目是纯 ArkTS（无 C++）、
# CI 也不用预览器，native 与 previewer 仍必须存在，否则报 native:20 / previewer:20 缺失。
COMPONENTS="ets js native previewer toolchains"

if [ -f "${ROOT}/.ready" ]; then
  echo "==> SDK 命中缓存，跳过下载"
  du -sh "${ROOT}" || true
  exit 0
fi

URL="https://repo.huaweicloud.com/openharmony/os/${VER}/ohos-sdk-windows_linux-public.tar.gz"
TAR=/tmp/ohos-sdk.tar.gz
RAW=/tmp/sdk-raw

echo "==> 下载 OpenHarmony SDK（约 3.2GB，首次较慢）: ${URL}"
df -h / | tail -1
curl -fSL --retry 3 --retry-delay 5 -o "${TAR}" "${URL}"
ls -lh "${TAR}"

echo "==> 解包（只取 linux 目录）"
rm -rf "${RAW}" && mkdir -p "${RAW}"
tar -xzf "${TAR}" -C "${RAW}"
rm -f "${TAR}"                       # 立刻释放 3.2GB
LINUX_DIR="$(find "${RAW}" -maxdepth 3 -type d -name linux | head -1)"
if [ -z "${LINUX_DIR}" ]; then
  echo "ERROR: 未找到 linux 目录，实际结构："
  find "${RAW}" -maxdepth 3 -type d | head -30
  exit 1
fi
echo "linux dir = ${LINUX_DIR}"
ls -la "${LINUX_DIR}"

echo "==> 逐个解压组件（直接落到目标目录，不留中间副本）"
DEST="${ROOT}/20"                    # 稍后按真实 apiVersion 改名
mkdir -p "${DEST}"
for c in ${COMPONENTS}; do
  z="$(ls "${LINUX_DIR}/${c}-"*.zip 2>/dev/null | head -1 || true)"
  if [ -z "${z}" ]; then
    echo "WARN: 未找到 ${c} 组件包"
    continue
  fi
  mkdir -p "${DEST}/${c}"
  unzip -q -o "${z}" -d "${DEST}/${c}"
  # 某些包内还有一层同名目录，拍平
  inner="$(find "${DEST}/${c}" -maxdepth 1 -mindepth 1 -type d | head -1)"
  if [ -n "${inner}" ] && [ ! -f "${DEST}/${c}/oh-uni-package.json" ]; then
    mv "${inner}"/* "${DEST}/${c}/" 2>/dev/null || true
    rmdir "${inner}" 2>/dev/null || true
  fi
  rm -f "${z}"          # 解压完立刻删掉该组件的 zip，避免累计撑爆 runner 磁盘
  echo "  ${c} ok"
done
rm -rf "${RAW}"                      # 释放中间目录

PKG="$(find "${DEST}" -name oh-uni-package.json | head -1 || true)"
API="$(python3 -c "import json;print(json.load(open('${PKG}'))['apiVersion'])" 2>/dev/null || echo 20)"
echo "==> SDK apiVersion = ${API}"
[ -n "${PKG}" ] && cat "${PKG}" || true

if [ "${API}" != "20" ]; then
  mv "${DEST}" "${ROOT}/${API}"
  DEST="${ROOT}/${API}"
fi

echo "==> 兼容布局：符号链接（不复制，避免缓存翻倍）"
mkdir -p "${ROOT}/default"
ln -sfn "${DEST}" "${ROOT}/default/openharmony"

touch "${ROOT}/.ready"
echo "==> SDK 就绪，体积："
du -sh "${ROOT}"
find "${ROOT}" -maxdepth 3 -type d | head -20
df -h / | tail -1
