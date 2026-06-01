#!/usr/bin/env bash

# 用途：
# 1. 使用 PRISM 仓库自带的 repo/test data/D18.fa 作为小测试输入
# 2. 将测试 FASTA 转成临时 FASTQ，使后续 Kraken2 classified-out 保持 FASTQ 格式
# 3. 调用当前搭建好的 PRISM 数据库、宿主索引和运行流程
#
# 默认输入：
#   ${PRISM_ROOT}/test data/D18.fa
#
# 默认输出：
#   ${PROJECT_ROOT}/02fastq/D18_repo_testdata_prism/
#
# 运行前必须完成：
# 1. conda activate prism
# 2. 准备好 Kraken2、BLAST core_nt、Minimap2、STAR、genbank 等 PRISM 资源
# 3. 若脚本无法自动识别项目目录，请显式设置 PROJECT_ROOT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../00script/repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../repo" ]]; then
  # 兼容本仓库克隆后的目录结构：scripts/ 与 repo/ 同级。
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  PROJECT_ROOT="${HOME}/PRISM"
fi

if [[ -d "${PROJECT_ROOT}/00script/repo" ]]; then
  PRISM_ROOT="${PROJECT_ROOT}/00script/repo"
elif [[ -d "${PROJECT_ROOT}/repo" ]]; then
  PRISM_ROOT="${PROJECT_ROOT}/repo"
else
  echo "[错误] 找不到 PRISM 源码目录。请确认存在 ${PROJECT_ROOT}/00script/repo 或 ${PROJECT_ROOT}/repo"
  exit 1
fi

SAMPLE="${SAMPLE:-D18}"
TEST_FASTA="${TEST_FASTA:-${PRISM_ROOT}/test data/${SAMPLE}.fa}"
STAGED_INPUT_DIR="${STAGED_INPUT_DIR:-${PROJECT_ROOT}/02fastq/repo_testdata_input}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/02fastq/${SAMPLE}_repo_testdata_prism}"

THREADS="${THREADS:-16}"
KRAKEN2_EXTRA_OPTS="${KRAKEN2_EXTRA_OPTS:---memory-mapping}"
STAR_GENOME_LOAD="${STAR_GENOME_LOAD:-NoSharedMemory}"
USE_CUSTOM_DB="${USE_CUSTOM_DB:-FALSE}"
MIN_READ_PER="${MIN_READ_PER:-10000}"
MIN_UNIQ_FRAC="${MIN_UNIQ_FRAC:-5}"
MAX_SAMPLE="${MAX_SAMPLE:-100}"
MIN_QCOVS="${MIN_QCOVS:-80}"

REF_ROOT="${PROJECT_ROOT}/02ref"
KRAKEN_DB="${KRAKEN_DB:-${REF_ROOT}/kraken2/prism_kraken2_recommended}"
MINIMAP2_INDEX="${MINIMAP2_INDEX:-${REF_ROOT}/host/hg38.minimap2/hg38.mmi}"
STAR_GENOME_DIR="${STAR_GENOME_DIR:-${REF_ROOT}/host/hg38.star}"
BLAST_DB="${BLAST_DB:-${REF_ROOT}/blast/core_nt/core_nt}"
ACCESSION_MAP="${PRISM_ROOT}/sorted_accession_map.txt"
MODEL_TAXID_FILE="${PRISM_ROOT}/model_org_taxids.txt"

KRAKEN2_BIN="$(command -v kraken2 || true)"
SEQKIT_BIN="$(command -v seqkit || true)"
MINIMAP2_BIN="$(command -v minimap2 || true)"
STAR_BIN="$(command -v STAR || true)"
BLASTN_BIN="$(command -v blastn || true)"
RSCRIPT_BIN="$(command -v Rscript || true)"
AWK_BIN="$(command -v awk || true)"

if [[ -z "${BLASTN_BIN}" ]]; then
  BLAST_BIN_DIR=""
else
  BLAST_BIN_DIR="$(dirname "${BLASTN_BIN}")"
fi

check_executable() {
  local label="$1"
  local exe="$2"
  if [[ -z "${exe}" || ! -x "${exe}" ]]; then
    echo "[错误] 找不到可执行程序 ${label}。请先激活 prism 环境，或把它加入 PATH。"
    exit 1
  fi
}

check_path() {
  local label="$1"
  local path="$2"
  if [[ ! -e "${path}" ]]; then
    echo "[错误] 缺少 ${label}: ${path}"
    exit 1
  fi
}

check_blast_db() {
  local prefix="$1"
  if [[ ! -e "${prefix}.nhr" && ! -e "${prefix}.00.nhr" && ! -e "${prefix}.ndb" ]]; then
    echo "[错误] BLAST 数据库前缀无效: ${prefix}"
    echo "       请确认 BLAST_DB 指向数据库前缀，而不是目录。"
    exit 1
  fi
}

fasta_to_fastq() {
  local in_fasta="$1"
  local out_fastq="$2"
  "${AWK_BIN}" '
    function emit_record() {
      if (name != "") {
        print "@" name
        print seq
        print "+"
        qual = ""
        for (i = 1; i <= length(seq); i++) {
          qual = qual "I"
        }
        print qual
      }
    }
    /^>/ {
      emit_record()
      name = substr($0, 2)
      seq = ""
      next
    }
    {
      gsub(/[ \t\r]/, "")
      seq = seq $0
    }
    END {
      emit_record()
    }
  ' "${in_fasta}" > "${out_fastq}"
}

echo "[检查] PRISM repo test data 流程"
echo "[检查] PROJECT_ROOT=${PROJECT_ROOT}"
echo "[检查] PRISM_ROOT=${PRISM_ROOT}"
echo "[检查] SAMPLE=${SAMPLE}"
echo "[检查] TEST_FASTA=${TEST_FASTA}"
echo "[检查] OUT_DIR=${OUT_DIR}"
echo "[检查] KRAKEN2_EXTRA_OPTS=${KRAKEN2_EXTRA_OPTS}"
echo "[检查] STAR_GENOME_LOAD=${STAR_GENOME_LOAD}"
echo "[检查] USE_CUSTOM_DB=${USE_CUSTOM_DB}"

check_executable "kraken2" "${KRAKEN2_BIN}"
check_executable "seqkit" "${SEQKIT_BIN}"
check_executable "minimap2" "${MINIMAP2_BIN}"
check_executable "STAR" "${STAR_BIN}"
check_executable "blastn" "${BLASTN_BIN}"
check_executable "Rscript" "${RSCRIPT_BIN}"
check_executable "awk" "${AWK_BIN}"

check_path "测试 FASTA" "${TEST_FASTA}"
check_path "Kraken2 数据库目录" "${KRAKEN_DB}"
check_path "Minimap2 宿主索引" "${MINIMAP2_INDEX}"
check_path "STAR genomeDir" "${STAR_GENOME_DIR}"
check_blast_db "${BLAST_DB}"
check_path "model_org_taxids.txt" "${MODEL_TAXID_FILE}"
check_path "genbank 目录" "${PRISM_ROOT}/genbank"

if [[ "${USE_CUSTOM_DB}" == "TRUE" || "${USE_CUSTOM_DB}" == "true" || "${USE_CUSTOM_DB}" == "T" ]]; then
  check_path "sorted_accession_map.txt" "${ACCESSION_MAP}"
elif [[ ! -f "${ACCESSION_MAP}" ]]; then
  echo "[提示] 未找到 sorted_accession_map.txt；当前 USE_CUSTOM_DB=${USE_CUSTOM_DB}，本次不会创建 custom BLAST DB。"
fi

mkdir -p "${STAGED_INPUT_DIR}" "${OUT_DIR}"

STAGED_FASTQ="${STAGED_INPUT_DIR}/${SAMPLE}.fastq"
echo "[准备] 将测试 FASTA 转成临时 FASTQ: ${STAGED_FASTQ}"
fasta_to_fastq "${TEST_FASTA}" "${STAGED_FASTQ}"

echo "[运行] 开始执行 PRISM repo/test data 测试流程"

set +e
"${RSCRIPT_BIN}" "${PRISM_ROOT}/PRISM.R" \
  --sample "${SAMPLE}" \
  --data_path "${STAGED_INPUT_DIR}" \
  --kraken_path "${KRAKEN2_BIN}" \
  --kraken_db_path "${KRAKEN_DB}" \
  --seqkit_path "${SEQKIT_BIN}" \
  --minimap2_path "${MINIMAP2_BIN}" \
  --minimap2_index "${MINIMAP2_INDEX}" \
  --kraken_extra_opts="${KRAKEN2_EXTRA_OPTS}" \
  --star_path "${STAR_BIN}" \
  --star_genome_dir "${STAR_GENOME_DIR}" \
  --star_genome_load "${STAR_GENOME_LOAD}" \
  --model_org_taxids "${MODEL_TAXID_FILE}" \
  --blast_path "${BLAST_BIN_DIR}" \
  --blast_db_path "${BLAST_DB}" \
  --prism_path "${PRISM_ROOT}" \
  --paired FALSE \
  --fq1_end ".fastq" \
  --threads "${THREADS}" \
  --min_read_per "${MIN_READ_PER}" \
  --min_uniq_frac "${MIN_UNIQ_FRAC}" \
  --max_sample "${MAX_SAMPLE}" \
  --min_qcovs "${MIN_QCOVS}" \
  --use_custom_db "${USE_CUSTOM_DB}" \
  --out_path "${OUT_DIR}"
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
  echo "[错误] PRISM 运行失败，退出码: ${status}"
  echo "[提示] 如果失败在 Kraken2 analysis 且退出码为 9，通常是 kraken2 被系统杀掉，常见原因是内存不足。"
  echo "[提示] 当前 Kraken2 额外参数为: ${KRAKEN2_EXTRA_OPTS}"
  echo "[提示] 建议确认参数中包含 --memory-mapping，或改用更小/已预加载/适合服务器内存的 Kraken2 数据库。"
  echo "[提示] 日志文件通常在: ${OUT_DIR}/data/${SAMPLE}_PRISM.log"
  exit "${status}"
fi

echo "[完成] PRISM repo/test data 测试流程结束"
echo "[结果] 输出目录: ${OUT_DIR}"
echo "[结果] 物种汇总: ${OUT_DIR}/${SAMPLE}-counts.csv"
echo "[结果] read 级结果: ${OUT_DIR}/${SAMPLE}-results.csv"
echo "[结果] 日志文件: ${OUT_DIR}/data/${SAMPLE}_PRISM.log"
echo "[结果] 最终 FASTA: ${OUT_DIR}/${SAMPLE}_1.fa"

if [[ -f "${PRISM_ROOT}/test data/${SAMPLE}-counts.csv" || -f "${PRISM_ROOT}/test data/${SAMPLE}-results.csv" ]]; then
  echo "[参考] 仓库自带参考结果位于: ${PRISM_ROOT}/test data/${SAMPLE}-counts.csv 和 ${PRISM_ROOT}/test data/${SAMPLE}-results.csv"
fi
