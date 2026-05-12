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
# 4. `k2 download-library` 支持 `--resume`
# 5. 本脚本会：
#    - 已完成的 library 直接跳过
#    - 存在但未完成的 library 自动尝试断点续传
# 6. taxonomy 当前采用“完成标记”方式判断是否需要重下

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

K2_THREADS="${K2_THREADS:-6}"
KR_SOURCE_ROOT="${PROJECT_ROOT}/02ref/kraken2_sources"
KR_SOURCE_DIR="${KR_SOURCE_ROOT}/prism_kraken2_recommended"
MARKER_DIR="${KR_SOURCE_DIR}/.download_markers"
TAXONOMY_MARKER="${MARKER_DIR}/taxonomy.done"

echo "[检查] 检查 k2"
if ! command -v k2 >/dev/null 2>&1; then
  echo "[错误] 未找到 k2"
  exit 1
fi

mkdir -p "${KR_SOURCE_ROOT}" "${KR_SOURCE_DIR}" "${MARKER_DIR}"

if [[ ! -f "${TAXONOMY_MARKER}" ]]; then
  if [[ -d "${KR_SOURCE_DIR}/taxonomy" ]]; then
    echo "[重下] taxonomy 目录存在但没有完成标记，删除后重新下载"
    rm -rf "${KR_SOURCE_DIR}/taxonomy"
  fi
  echo "[下载] Kraken2 taxonomy"
  k2 download-taxonomy --db "${KR_SOURCE_DIR}"
  touch "${TAXONOMY_MARKER}"
else
  echo "[跳过] taxonomy 已完成"
fi

for lib in archaea bacteria viral human UniVec_Core fungi; do
  lib_dir="${KR_SOURCE_DIR}/library/${lib}"
  lib_marker="${MARKER_DIR}/${lib}.done"

  if [[ -f "${lib_marker}" ]]; then
    echo "[跳过] Kraken2 library 已完成: ${lib}"
    continue
  fi

  if [[ -d "${lib_dir}" ]]; then
    echo "[续传] 检测到未完成的 library，尝试断点续传: ${lib}"
    k2 download-library --resume --db "${KR_SOURCE_DIR}" --library "${lib}" --threads "${K2_THREADS}"
  else
    echo "[下载] Kraken2 library: ${lib}"
    k2 download-library --db "${KR_SOURCE_DIR}" --library "${lib}" --threads "${K2_THREADS}"
  fi

  touch "${lib_marker}"
done

echo "[完成] Kraken2 源数据目录:"
echo "${KR_SOURCE_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] 当前 k2 下载线程数: ${K2_THREADS}"
