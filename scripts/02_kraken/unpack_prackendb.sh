#!/usr/bin/env bash

# 用途：
# 1. 使用 pigz 并行解压已经下载完成的 PrackenDB 数据库压缩包
# 2. 默认直接展开到下游分析所需的标准目录
#
# 输入：
#   ${PROJECT_ROOT}/02ref/kraken2_prackendb/k2_NCBI_reference_20251007.tar.gz
#
# 输出：
#   ${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
#
# 推荐用法：
#   bash ${PROJECT_ROOT}/00script/02_kraken/unpack_prackendb.sh
#
# 可调参数：
#   PROJECT_ROOT    项目目录
#   ARCHIVE_PATH    压缩包路径
#   OUT_DIR         解压目录
#
# 说明：
# 1. 这个脚本会把数据库直接解压到 `${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended`
# 2. 这样下游分析脚本可直接使用：
#    KRAKEN_DB="${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended"

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

ARCHIVE_PATH="${ARCHIVE_PATH:-${PROJECT_ROOT}/02ref/kraken2_prackendb/k2_NCBI_reference_20251007.tar.gz}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended}"

echo "[检查] 依赖程序"
for exe in tar pigz; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "[错误] 找不到压缩包: ${ARCHIVE_PATH}"
  exit 1
fi

mkdir -p "${OUT_DIR}"

echo "[校验] gzip 完整性检查"
pigz -t "${ARCHIVE_PATH}"

echo "[解压] 开始并行解压到: ${OUT_DIR}"
tar -I pigz -xvf "${ARCHIVE_PATH}" -C "${OUT_DIR}"

echo "[完成] PrackenDB 已解压"
echo "[结果] 解压目录: ${OUT_DIR}"
