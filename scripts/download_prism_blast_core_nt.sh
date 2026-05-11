#!/usr/bin/env bash

# 用途：
# 1. 基于已下载好的 NCBI BLAST core_nt 源数据生成 PRISM 所需 accession map
# 2. 复制 sorted_accession_map.txt 到 PRISM 仓库
#
# 使用场景：
# 1. 在服务器上运行
# 2. 先把下载机生成的 core_nt 源数据目录复制到本机

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
DB_ROOT="${PROJECT_ROOT}/02ref/blast_sources"
CORE_NT_DIR="${DB_ROOT}/core_nt"
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
  echo "[错误] 未找到 core_nt 源数据目录: ${CORE_NT_DIR}"
  echo "       请先在下载机上运行 download_prism_blast_core_nt_sources.sh，然后复制到服务器。"
  exit 1
fi

if [[ ! -f "${BLAST_DB_PREFIX}.ndb" && ! -f "${BLAST_DB_PREFIX}.00.nhr" && ! -f "${BLAST_DB_PREFIX}.nhr" ]]; then
  echo "[警告] 未检测到已格式化的 BLAST 数据库前缀文件，但仍将尝试从源目录导出映射。"
fi

echo "[生成] 提取 taxid_accession_map.tsv"
blastdbcmd -db "${BLAST_DB_PREFIX}" -entry all -outfmt "%T %a" > "${TAXID_ACCESSION_MAP}"

echo "[生成] 生成 sorted_accession_map.txt"
sort -k2,2 "${TAXID_ACCESSION_MAP}" > "${SORTED_ACCESSION_MAP}"

cp "${SORTED_ACCESSION_MAP}" "${PRISM_ROOT}/sorted_accession_map.txt"

echo "[完成] accession map:"
echo "${PRISM_ROOT}/sorted_accession_map.txt"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"

