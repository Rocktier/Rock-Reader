#!/usr/bin/env bash
# 在 CI 上准备 OpenHarmony SDK（公开下载，无需华为账号登录）
# 用途：为 ArkTS/ArkUI 代码做**编译校验**；正式 HarmonyOS 包仍由 default product 产出
# 依据：家族 findings §7（CI 构建 HAP 可行性）+ §14（构建一律走 GitHub Actions）
set -euo pipefail

VER="${1:-6.0.0.2-Release}"
ROOT="${PWD}/.ohos-sdk"
COMPONENTS="ets js native previewer toolchains"

if [ -f "${ROOT}/.ready" ]; then
  echo "==> SDK 命中缓存，跳过下载"
  find "${ROOT}" -maxdepth 2 -type d | head -30
  exit 0
fi

URL="https://repo.huaweicloud.com/openharmony/os/${VER}/ohos-sdk-windows_linux-public.tar.gz"
echo "==> 下载 OpenHarmony SDK: ${URL}"
curl -fSL --retry 3 --retry-delay 5 -o /tmp/ohos-sdk.tar.gz "${URL}"
ls -lh /tmp/ohos-sdk.tar.gz

echo "==> 解包"
mkdir -p /tmp/sdk-raw
tar -xzf /tmp/ohos-sdk.tar.gz -C /tmp/sdk-raw
LINUX_DIR="$(find /tmp/sdk-raw -maxdepth 3 -type d -name linux | head -1)"
if [ -z "${LINUX_DIR}" ]; then
  echo "ERROR: 未找到 linux 目录，实际结构："
  find /tmp/sdk-raw -maxdepth 3 -type d | head -30
  exit 1
fi
echo "linux dir = ${LINUX_DIR}"
ls -la "${LINUX_DIR}"

echo "==> 解压各组件"
WORK=/tmp/sdk-unzip
rm -rf "${WORK}" && mkdir -p "${WORK}"
for c in ${COMPONENTS}; do
  z="$(ls "${LINUX_DIR}/${c}-"*.zip 2>/dev/null | head -1 || true)"
  if [ -z "${z}" ]; then
    echo "WARN: 未找到 ${c} 组件包"
    continue
  fi
  mkdir -p "${WORK}/${c}"
  unzip -q -o "${z}" -d "${WORK}/${c}"
  # 某些包里还有一层同名目录，拍平
  inner="$(find "${WORK}/${c}" -maxdepth 1 -type d ! -path "${WORK}/${c}" | head -1)"
  if [ -n "${inner}" ] && [ ! -f "${WORK}/${c}/oh-uni-package.json" ]; then
    mv "${inner}"/* "${WORK}/${c}/" 2>/dev/null || true
  fi
  echo "  ${c} ok"
done

PKG="$(find "${WORK}" -name oh-uni-package.json | head -1 || true)"
API="$(python3 -c "import json,sys;print(json.load(open('${PKG}'))['apiVersion'])" 2>/dev/null || echo 20)"
echo "==> SDK apiVersion = ${API}"
[ -n "${PKG}" ] && cat "${PKG}" || true

echo "==> 落地双布局（兼容 hvigor 的不同解析路径）"
for layout in "${ROOT}/${API}" "${ROOT}/default/openharmony"; do
  mkdir -p "${layout}"
  for c in ${COMPONENTS}; do
    if [ -d "${WORK}/${c}" ]; then
      mkdir -p "${layout}/${c}"
      cp -R "${WORK}/${c}/." "${layout}/${c}/"
    fi
  done
done

touch "${ROOT}/.ready"
echo "==> SDK 就绪："
find "${ROOT}" -maxdepth 3 -type d | head -30
