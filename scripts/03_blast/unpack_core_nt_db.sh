#!/usr/bin/env bash

# 用途：
# 1. 使用 pigz 并行解压已经下载完成的 Kraken 官方 core_nt 数据库压缩包
# 2. 将数据库内容展开到指定目录，便于后续直接使用
#
# 输入：
#   ${PROJECT_ROOT}/02ref/blast/core_nt_download/k2_core_nt_20251015.tar.gz
#
# 输出：
#   ${PROJECT_ROOT}/02ref/blast/core_nt
#
# 推荐用法：
#   bash ${PROJECT_ROOT}/00script/03_blast/unpack_core_nt_db.sh
#
# 可调参数：
#   PROJECT_ROOT    项目目录
#   ARCHIVE_PATH    压缩包路径
#   OUT_DIR         解压目录

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

ARCHIVE_PATH="${ARCHIVE_PATH:-${PROJECT_ROOT}/02ref/blast/core_nt_download/k2_core_nt_20251015.tar.gz}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/02ref/blast/core_nt}"

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

echo "[完成] core_nt 数据库已解压"
echo "[结果] 解压目录: ${OUT_DIR}"
