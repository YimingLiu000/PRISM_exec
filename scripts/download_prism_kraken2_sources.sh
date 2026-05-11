#!/usr/bin/env bash

# 用途：
# 1. 仅下载 PRISM 推荐 Kraken2 数据库所需的原始源数据
# 2. 不执行最终 build
#
# 使用场景：
# 1. 在网络快但磁盘空间有限的机器（如 WSL）上运行
# 2. 然后把下载好的源数据目录复制到服务器
#
# 下载内容：
# - taxonomy
# - archaea / bacteria / viral / human / UniVec_Core / fungi
#
# 说明：
# 1. 这个脚本不会构建最终 `.k2d` 数据库
# 2. 最终 build 请在服务器上运行 `build_prism_kraken2_recommended.sh`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
elif [[ -d "${SCRIPT_DIR}/repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../00script/repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  PROJECT_ROOT="${HOME}/PRISM"
fi

KRAKEN_DOWNLOAD_OPTS="${KRAKEN_DOWNLOAD_OPTS:---use-ftp}"
KR_SOURCE_ROOT="${PROJECT_ROOT}/02ref/kraken2_sources"
KR_SOURCE_DIR="${KR_SOURCE_ROOT}/prism_kraken2_recommended"

echo "[检查] 检查 kraken2-build"
if ! command -v kraken2-build >/dev/null 2>&1; then
  echo "[错误] 未找到 kraken2-build"
  exit 1
fi

mkdir -p "${KR_SOURCE_ROOT}" "${KR_SOURCE_DIR}"

if [[ ! -d "${KR_SOURCE_DIR}/taxonomy" ]]; then
  echo "[下载] Kraken2 taxonomy"
  kraken2-build --download-taxonomy ${KRAKEN_DOWNLOAD_OPTS} --skip-maps --db "${KR_SOURCE_DIR}"
else
  echo "[跳过] taxonomy 已存在"
fi

for lib in archaea bacteria viral human UniVec_Core fungi; do
  echo "[下载] Kraken2 library: ${lib}"
  kraken2-build --download-library "${lib}" ${KRAKEN_DOWNLOAD_OPTS} --db "${KR_SOURCE_DIR}"
done

echo "[完成] Kraken2 源数据目录:"
echo "${KR_SOURCE_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] 当前 Kraken 下载参数: ${KRAKEN_DOWNLOAD_OPTS}"

