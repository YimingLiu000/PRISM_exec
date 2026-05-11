#!/usr/bin/env bash

# 用途：
# 1. 下载人源参考基因组 GRCh38
# 2. 基于该参考序列构建 Minimap2 宿主索引
# 3. 基于该参考序列构建 STAR 宿主索引
#
# 说明：
# 1. 这里使用 NCBI RefSeq human reference genome
# 2. 目标是给 PRISM 的宿主去除步骤提供索引
# 3. 这个脚本优先构建“可运行的基础索引”，不额外处理复杂注释

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

THREADS=32
DB_ROOT="${PROJECT_ROOT}/02ref/host"
HUMAN_ACC="GCF_000001405.40"
PKG_ZIP="${DB_ROOT}/GRCh38_refseq.zip"
PKG_DIR="${DB_ROOT}/GRCh38_refseq"
MINIMAP2_DIR="${DB_ROOT}/hg38.minimap2"
STAR_DIR="${DB_ROOT}/hg38.star"
MINIMAP2_INDEX="${MINIMAP2_DIR}/hg38.mmi"

echo "[检查] 检查依赖软件"
for exe in datasets unzip minimap2 STAR find; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 未找到命令: ${exe}"
    exit 1
  fi
done

mkdir -p "${DB_ROOT}" "${MINIMAP2_DIR}" "${STAR_DIR}"

if [[ ! -f "${PKG_ZIP}" ]]; then
  echo "[下载] 下载 GRCh38 RefSeq 参考基因组"
  datasets download genome accession "${HUMAN_ACC}" \
    --filename "${PKG_ZIP}" \
    --include genome
else
  echo "[跳过] 已存在下载包: ${PKG_ZIP}"
fi

if [[ ! -d "${PKG_DIR}" ]]; then
  echo "[解压] 解压 GRCh38 数据包"
  unzip -q "${PKG_ZIP}" -d "${PKG_DIR}"
else
  echo "[跳过] 已存在解压目录: ${PKG_DIR}"
fi

HUMAN_FASTA="$(find "${PKG_DIR}" -type f -name '*_genomic.fna' | head -n 1)"

if [[ -z "${HUMAN_FASTA}" ]]; then
  echo "[错误] 未找到 human genomic FASTA"
  exit 1
fi

echo "[信息] Human FASTA:"
echo "${HUMAN_FASTA}"

if [[ ! -f "${MINIMAP2_INDEX}" ]]; then
  echo "[构建] Minimap2 索引"
  minimap2 -d "${MINIMAP2_INDEX}" "${HUMAN_FASTA}"
else
  echo "[跳过] Minimap2 索引已存在"
fi

if [[ ! -f "${STAR_DIR}/Genome" ]]; then
  echo "[构建] STAR 索引"
  STAR \
    --runMode genomeGenerate \
    --runThreadN "${THREADS}" \
    --genomeDir "${STAR_DIR}" \
    --genomeFastaFiles "${HUMAN_FASTA}"
else
  echo "[跳过] STAR 索引已存在"
fi

echo "[完成] Minimap2 索引:"
echo "${MINIMAP2_INDEX}"
echo "[完成] STAR genomeDir:"
echo "${STAR_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
