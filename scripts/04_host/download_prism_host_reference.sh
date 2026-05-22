#!/usr/bin/env bash

# 用途：
# 1. 仅下载 PRISM 宿主索引所需的人源参考基因组
# 2. 不执行 Minimap2 / STAR 构建
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

HOST_SOURCE_ROOT="${PROJECT_ROOT}/02ref/host_sources"
HOST_SOURCE_DIR="${HOST_SOURCE_ROOT}/GRCh38_refseq"
PKG_ZIP="${HOST_SOURCE_ROOT}/GRCh38_refseq.zip"
HUMAN_ACC="GCF_000001405.40"

echo "[检查] 检查 datasets/unzip"
for exe in datasets unzip; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 未找到命令: ${exe}"
    exit 1
  fi
done

mkdir -p "${HOST_SOURCE_ROOT}" "${HOST_SOURCE_DIR}"

if [[ ! -f "${PKG_ZIP}" ]]; then
  echo "[下载] 下载 GRCh38 RefSeq 参考基因组"
  datasets download genome accession "${HUMAN_ACC}" \
    --filename "${PKG_ZIP}" \
    --include genome
else
  echo "[跳过] 已存在下载包: ${PKG_ZIP}"
fi

if [[ ! -d "${HOST_SOURCE_DIR}/ncbi_dataset/data" ]]; then
  echo "[解压] 解压 GRCh38 数据包"
  unzip -q "${PKG_ZIP}" -d "${HOST_SOURCE_DIR}"
else
  echo "[跳过] 已存在解压目录: ${HOST_SOURCE_DIR}/ncbi_dataset/data"
fi

HUMAN_FASTA="$(find "${HOST_SOURCE_DIR}" -type f -name '*_genomic.fna' | head -n 1)"
if [[ -z "${HUMAN_FASTA}" ]]; then
  echo "[错误] 未找到 human genomic FASTA"
  exit 1
fi

rm -f "${PKG_ZIP}"

echo "[完成] 宿主源数据目录:"
echo "${HOST_SOURCE_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"

