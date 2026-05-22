#!/usr/bin/env bash

# 用途：
# 1. 基于已下载好的 BLAST core_nt 数据库生成 PRISM 所需 accession map
# 2. 复制 sorted_accession_map.txt 到 PRISM 仓库
#
# 使用场景：
# 1. 在服务器上运行
# 2. 既兼容“官方已构建数据库直接下载并解压”的方式
# 3. 也兼容“两步法下载源数据”的方式

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

PRISM_ROOT="${PROJECT_ROOT}/00script/repo"
CORE_NT_DIR="${PROJECT_ROOT}/02ref/blast/core_nt"
BLAST_DB_NAME="core_nt"

BLAST_DB_PREFIX="${CORE_NT_DIR}/${BLAST_DB_NAME}"
TAXID_ACCESSION_MAP="${CORE_NT_DIR}/taxid_accession_map.tsv"
SORTED_ACCESSION_MAP="${CORE_NT_DIR}/sorted_accession_map.txt"

echo "[检查] 检查 BLAST 相关命令"
for exe in blastdbcmd sort; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 未找到命令: ${exe}"
    exit 1
  fi
done

if [[ ! -d "${PRISM_ROOT}" ]]; then
  echo "[错误] PRISM 仓库不存在: ${PRISM_ROOT}"
  exit 1
fi

if [[ ! -d "${CORE_NT_DIR}" ]]; then
  echo "[错误] 未找到 core_nt 数据目录: ${CORE_NT_DIR}"
  echo "       请先准备 BLAST core_nt 数据库，并确保最终落到该标准目录。"
  exit 1
fi

if [[ ! -f "${BLAST_DB_PREFIX}.ndb" && ! -f "${BLAST_DB_PREFIX}.00.nhr" && ! -f "${BLAST_DB_PREFIX}.nhr" ]]; then
  echo "[错误] 未检测到已格式化的 BLAST 数据库前缀文件:"
  echo "       ${BLAST_DB_PREFIX}"
  exit 1
fi

echo "[生成] 提取 taxid_accession_map.tsv"
blastdbcmd -db "${BLAST_DB_PREFIX}" -entry all -outfmt "%T %a" > "${TAXID_ACCESSION_MAP}"

echo "[生成] 生成 sorted_accession_map.txt"
sort -k1,1 "${TAXID_ACCESSION_MAP}" > "${SORTED_ACCESSION_MAP}"

cp "${SORTED_ACCESSION_MAP}" "${PRISM_ROOT}/sorted_accession_map.txt"

echo "[完成] accession map:"
echo "${PRISM_ROOT}/sorted_accession_map.txt"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] 当前使用的 core_nt 数据目录: ${CORE_NT_DIR}"
