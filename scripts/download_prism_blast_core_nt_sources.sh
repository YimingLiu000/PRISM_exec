#!/usr/bin/env bash

# 用途：
# 1. 仅下载 NCBI 预格式化 BLAST 数据库 core_nt
# 2. 仅下载 taxdb
# 3. 不生成 PRISM 的 accession map
#
# 使用场景：
# 1. 在网络快但磁盘空间有限的机器（如 WSL）上运行
# 2. 然后把下载好的源数据目录复制到服务器

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

echo "[检查] 检查 BLAST 相关命令"
for exe in update_blastdb.pl; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 未找到命令: ${exe}"
    exit 1
  fi
done

if [[ ! -d "${PRISM_ROOT}" ]]; then
  echo "[错误] PRISM 仓库不存在: ${PRISM_ROOT}"
  exit 1
fi

mkdir -p "${CORE_NT_DIR}"
cd "${CORE_NT_DIR}"

echo "[下载] 开始下载 core_nt"
update_blastdb.pl --decompress "${BLAST_DB_NAME}"

echo "[下载] 开始下载 taxdb"
update_blastdb.pl --decompress taxdb

echo "[完成] BLAST 源数据目录:"
echo "${CORE_NT_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"

