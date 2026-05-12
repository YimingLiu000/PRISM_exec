#!/usr/bin/env bash

# 用途：
# 1. 使用新版 `k2 build` 基于已下载的源数据构建最终 Kraken2 数据库
#
# 说明：
# 1. 下载阶段使用 `k2 download-*`
# 2. 构建阶段使用 `k2 build`
# 3. 后续 PRISM 分析仍旧使用 `kraken2`

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

THREADS="${THREADS:-32}"
KRAKEN_SOURCE_DIR="${KRAKEN_SOURCE_DIR:-${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended}"
DB_ROOT="${PROJECT_ROOT}/02ref/kraken2"
DB_DIR="${DB_ROOT}/prism_kraken2_recommended"

echo "[检查] 检查 k2"
if ! command -v k2 >/dev/null 2>&1; then
  echo "[错误] 未找到 k2"
  exit 1
fi

if [[ ! -d "${KRAKEN_SOURCE_DIR}/taxonomy" ]]; then
  echo "[错误] 未找到 Kraken2 taxonomy 源数据: ${KRAKEN_SOURCE_DIR}/taxonomy"
  echo "       请先在下载机上运行 download_prism_kraken2_sources.sh，然后把源数据复制过来。"
  exit 1
fi

if [[ ! -d "${KRAKEN_SOURCE_DIR}/library" ]]; then
  echo "[错误] 未找到 Kraken2 library 源数据: ${KRAKEN_SOURCE_DIR}/library"
  echo "       请先在下载机上运行 download_prism_kraken2_sources.sh，然后把源数据复制过来。"
  exit 1
fi

mkdir -p "${DB_ROOT}" "${DB_DIR}"

echo "[同步] 复制 taxonomy 到构建目录"
rsync -a --delete "${KRAKEN_SOURCE_DIR}/taxonomy/" "${DB_DIR}/taxonomy/"

echo "[同步] 复制 library 到构建目录"
rsync -a --delete "${KRAKEN_SOURCE_DIR}/library/" "${DB_DIR}/library/"

echo "[构建] 开始 build"
k2 build --threads "${THREADS}" --db "${DB_DIR}"

echo "[完成] Kraken2 数据库目录:"
echo "${DB_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] Kraken 源数据目录: ${KRAKEN_SOURCE_DIR}"

