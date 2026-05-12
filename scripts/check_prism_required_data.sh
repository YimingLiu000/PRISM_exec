#!/usr/bin/env bash

# 用途：
# 1. 检查按 PRISM 推荐方式准备的数据是否齐全
# 2. 给出当前环境下应当传给 PRISM 的主要路径

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
REF_ROOT="${PROJECT_ROOT}/02ref"
HOST_SOURCE_DIR="${REF_ROOT}/host_sources/GRCh38_refseq"
KRAKEN_SOURCE_DIR="${REF_ROOT}/kraken2_sources/prism_kraken2_recommended"
KRAKEN_DB="${REF_ROOT}/kraken2/prism_kraken2_recommended"
BLAST_DB="${REF_ROOT}/blast/core_nt/core_nt"
MINIMAP2_INDEX="${REF_ROOT}/host/hg38.minimap2/hg38.mmi"
STAR_DIR="${REF_ROOT}/host/hg38.star"
ACCESSION_MAP="${PRISM_ROOT}/sorted_accession_map.txt"
GENBANK_DIR="${PRISM_ROOT}/genbank"
MODEL_TAXID_FILE="${PRISM_ROOT}/model_org_taxids.txt"

echo "[检查] PRISM 运行数据检查"

check_path() {
  local label="$1"
  local path="$2"
  if [[ -e "${path}" ]]; then
    echo "[OK] ${label}: ${path}"
  else
    echo "[缺失] ${label}: ${path}"
  fi
}

check_path "宿主源数据目录" "${HOST_SOURCE_DIR}"
check_path "Kraken2 源数据目录" "${KRAKEN_SOURCE_DIR}"
check_path "Kraken2 数据库目录" "${KRAKEN_DB}"
check_path "BLAST 数据库前缀（示意检查 .ndb/.nhr）" "${BLAST_DB}.ndb"
check_path "Minimap2 索引" "${MINIMAP2_INDEX}"
check_path "STAR genomeDir" "${STAR_DIR}"
check_path "sorted_accession_map.txt" "${ACCESSION_MAP}"
check_path "genbank 目录" "${GENBANK_DIR}"
check_path "model_org_taxids.txt" "${MODEL_TAXID_FILE}"

echo
echo "[建议] 运行 PRISM 时主要传参路径如下："
echo "--kraken_db_path ${KRAKEN_DB}"
echo "--blast_db_path ${BLAST_DB}"
echo "--minimap2_index ${MINIMAP2_INDEX}"
echo "--star_genome_dir ${STAR_DIR}"
echo "--model_org_taxids ${MODEL_TAXID_FILE}"
echo "[说明] 当前推断的 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] 宿主源数据目录: ${HOST_SOURCE_DIR}"
echo "[说明] Kraken 源数据目录: ${KRAKEN_SOURCE_DIR}"
