#!/usr/bin/env bash

# 用途：
# 1. 基于已下载的人源参考基因组构建 Minimap2 宿主索引
# 2. 基于已下载的人源参考基因组构建 STAR 宿主索引
#
# 说明：
# 1. 这里使用 NCBI RefSeq human reference genome
# 2. 目标是给 PRISM 的宿主去除步骤提供索引
# 3. 宿主参考基因组请先用 `download_prism_host_reference.sh` 下载到源数据目录

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
HOST_SOURCE_DIR="${HOST_SOURCE_DIR:-${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq}"
DB_ROOT="${PROJECT_ROOT}/02ref/host"
MINIMAP2_DIR="${DB_ROOT}/hg38.minimap2"
STAR_DIR="${DB_ROOT}/hg38.star"
MINIMAP2_INDEX="${MINIMAP2_DIR}/hg38.mmi"

echo "[检查] 检查依赖软件"
for exe in minimap2 STAR find; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 未找到命令: ${exe}"
    exit 1
  fi
done

mkdir -p "${DB_ROOT}" "${MINIMAP2_DIR}" "${STAR_DIR}"

if [[ ! -d "${HOST_SOURCE_DIR}" ]]; then
  echo "[错误] 未找到宿主源数据目录: ${HOST_SOURCE_DIR}"
  echo "       请先运行 download_prism_host_reference.sh，然后把源数据复制过来。"
  exit 1
fi

HUMAN_FASTA="$(find "${HOST_SOURCE_DIR}" -type f -name '*_genomic.fna' | head -n 1)"

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
echo "[说明] 宿主源数据目录: ${HOST_SOURCE_DIR}"
