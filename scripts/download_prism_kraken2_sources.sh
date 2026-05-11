#!/usr/bin/env bash

# 用途：
# 1. 使用新版 `k2` 命令下载 PRISM 推荐 Kraken2 数据库所需的原始源数据
# 2. 不执行最终 build
#
# 使用场景：
# 1. 在网络快但磁盘空间有限的机器（如 WSL）上运行
# 2. 然后把下载好的源数据目录复制到服务器
#
# 说明：
# 1. 这个脚本不会构建最终 `.k2d` 数据库
# 2. 最终 build 请在服务器上运行 `build_prism_kraken2_recommended.sh`
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

K2_THREADS="${K2_THREADS:-8}"
KR_SOURCE_ROOT="${PROJECT_ROOT}/02ref/kraken2_sources"
KR_SOURCE_DIR="${KR_SOURCE_ROOT}/prism_kraken2_recommended"

echo "[检查] 检查 k2"
if ! command -v k2 >/dev/null 2>&1; then
  echo "[错误] 未找到 k2"
  exit 1
fi

mkdir -p "${KR_SOURCE_ROOT}" "${KR_SOURCE_DIR}"

if [[ ! -d "${KR_SOURCE_DIR}/taxonomy" ]]; then
  echo "[下载] Kraken2 taxonomy"
  k2 download-taxonomy --db "${KR_SOURCE_DIR}"
else
  echo "[跳过] taxonomy 已存在"
fi

for lib in archaea bacteria viral human UniVec_Core fungi; do
  echo "[下载] Kraken2 library: ${lib}"
  k2 download-library --db "${KR_SOURCE_DIR}" --library "${lib}" --threads "${K2_THREADS}"
done

echo "[完成] Kraken2 源数据目录:"
echo "${KR_SOURCE_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] 当前 k2 下载线程数: ${K2_THREADS}"

