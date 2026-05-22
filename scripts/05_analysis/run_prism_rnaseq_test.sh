#!/usr/bin/env bash

# 用途：
# 1. 解压 ~/PRISM/01rawdata 中的测试 RNA-seq FASTQ.GZ
# 2. 调用 PRISM 对测试样本进行分析
# 3. 输出结果到 ~/PRISM/02fastq/<sample>_prism/
#
# 运行前必须完成：
# 1. conda env create -f ${PROJECT_ROOT}/00script/01_env/environment_prism.yml
# 2. conda activate prism
# 3. 执行 00script 中的数据准备脚本，完成：
#    - Kraken2 数据库，最终应位于：
#      ${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
#    - BLAST core_nt 数据库，最终应位于：
#      ${PROJECT_ROOT}/02ref/blast/core_nt
#    - Minimap2 宿主索引，最终应位于：
#      ${PROJECT_ROOT}/02ref/host/hg38.minimap2/hg38.mmi
#    - STAR 宿主索引，最终应位于：
#      ${PROJECT_ROOT}/02ref/host/hg38.star
#    - sorted_accession_map.txt，最终应位于：
#      ${PROJECT_ROOT}/00script/repo/sorted_accession_map.txt
#    - PRISM 仓库模型生物 taxid 文件：
#      ${PROJECT_ROOT}/00script/repo/model_org_taxids.txt
# 4. 将 PRISM 需要的 genbank/ 目录放到 ${PROJECT_ROOT}/00script/repo/genbank
#
# 注意：
# 1. 这个脚本默认测试样本名为 FUSCCTNBC001
# 2. 这个脚本默认直接对接 00script 中的推荐数据库路径
# 3. 第一次测试默认关闭 custom BLAST DB，减少额外前置依赖

set -euo pipefail

# -----------------------------
# 自动推断项目根目录
# 优先级：
# 1. 用户显式传入的 PROJECT_ROOT 环境变量
# 2. 当前脚本位于 ${PROJECT_ROOT}/00script/05_analysis，且 repo 在 ${PROJECT_ROOT}/00script/repo
# 3. 当前脚本位于 ${PROJECT_ROOT}/PRISM_linux_bundle/scripts，且 repo 在 ${PROJECT_ROOT}/00script/repo
# 4. 默认使用 ~/PRISM
# -----------------------------
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

# -----------------------------
# 基础目录
# -----------------------------
PRISM_ROOT="${PROJECT_ROOT}/00script/repo"
RAW_DIR="${PROJECT_ROOT}/01rawdata"
FASTQ_DIR="${PROJECT_ROOT}/02fastq"
SAMPLE="FUSCCTNBC001"

# -----------------------------
# 输入文件名后缀
# 说明：PRISM 的 sample 会与下面两个后缀直接拼接
# 例如：
#   sample = FUSCCTNBC001
#   fq1_end = _RNAseq_R1.fastq
# 最终得到文件：
#   FUSCCTNBC001_RNAseq_R1.fastq
# -----------------------------
FQ1_END="_RNAseq_R1.fastq"
FQ2_END="_RNAseq_R2.fastq"

# -----------------------------
# 按 00script 推荐方案约定的数据库路径
# 如果你改过数据库输出目录，请同步修改这里
# -----------------------------
REF_ROOT="${PROJECT_ROOT}/02ref"
KRAKEN_DB="${REF_ROOT}/kraken2/prism_kraken2_recommended"
MINIMAP2_INDEX="${REF_ROOT}/host/hg38.minimap2/hg38.mmi"
STAR_GENOME_DIR="${REF_ROOT}/host/hg38.star"
BLAST_DB="${REF_ROOT}/blast/core_nt/core_nt"
ACCESSION_MAP="${PRISM_ROOT}/sorted_accession_map.txt"

# -----------------------------
# 自动获取软件路径
# 前提：你已经激活 conda 环境 prism
# -----------------------------
KRAKEN2_BIN="$(command -v kraken2)"
SEQKIT_BIN="$(command -v seqkit)"
MINIMAP2_BIN="$(command -v minimap2)"
STAR_BIN="$(command -v STAR)"
BLASTN_BIN="$(command -v blastn)"
RSCRIPT_BIN="$(command -v Rscript)"

# blast_path 需要传“目录”，不是 blastn 文件本身
BLAST_BIN_DIR="$(dirname "${BLASTN_BIN}")"

# -----------------------------
# 前置检查
# -----------------------------
echo "[检查] 开始检查软件与目录"

for exe in "${KRAKEN2_BIN}" "${SEQKIT_BIN}" "${MINIMAP2_BIN}" "${STAR_BIN}" "${BLASTN_BIN}" "${RSCRIPT_BIN}"; do
  if [[ ! -x "${exe}" ]]; then
    echo "[错误] 可执行文件不存在或不可执行: ${exe}"
    exit 1
  fi
done

if [[ ! -d "${PRISM_ROOT}" ]]; then
  echo "[错误] PRISM 仓库目录不存在: ${PRISM_ROOT}"
  exit 1
fi

if [[ ! -d "${RAW_DIR}" ]]; then
  echo "[错误] 原始数据目录不存在: ${RAW_DIR}"
  exit 1
fi

if [[ ! -d "${PRISM_ROOT}/genbank" ]]; then
  echo "[错误] 缺少 PRISM 必需的 genbank 目录: ${PRISM_ROOT}/genbank"
  exit 1
fi

if [[ ! -f "${PRISM_ROOT}/model_org_taxids.txt" ]]; then
  echo "[错误] 缺少 model_org_taxids.txt: ${PRISM_ROOT}/model_org_taxids.txt"
  exit 1
fi

if [[ ! -f "${ACCESSION_MAP}" ]]; then
  echo "[错误] 缺少 sorted_accession_map.txt: ${ACCESSION_MAP}"
  echo "       请先运行 ${PROJECT_ROOT}/00script/03_blast/generate_sorted_accession_map.sh"
  exit 1
fi

for path in "${KRAKEN_DB}" "${MINIMAP2_INDEX}" "${STAR_GENOME_DIR}"; do
  if [[ ! -e "${path}" ]]; then
    echo "[错误] 路径不存在: ${path}"
    exit 1
  fi
done

# BLAST 数据库通常是前缀路径，因此这里只检查对应文件是否至少有一组存在
if [[ ! -e "${BLAST_DB}.nhr" && ! -e "${BLAST_DB}.00.nhr" && ! -e "${BLAST_DB}.ndb" ]]; then
  echo "[错误] 看起来 BLAST 数据库前缀无效: ${BLAST_DB}"
  echo "       请确认你传入的是数据库前缀，而不是目录。"
  exit 1
fi

mkdir -p "${FASTQ_DIR}"

# -----------------------------
# 解压测试数据
# 说明：
# 1. 当前 PRISM 脚本没有显式给 Kraken2 传 --gzip-compressed
# 2. 为减少兼容性问题，这里先解压为 .fastq
# 3. 如果目标文件已存在，则跳过解压
# -----------------------------
RAW_R1_GZ="${RAW_DIR}/${SAMPLE}_RNAseq_R1.fastq.gz"
RAW_R2_GZ="${RAW_DIR}/${SAMPLE}_RNAseq_R2.fastq.gz"
FASTQ_R1="${FASTQ_DIR}/${SAMPLE}${FQ1_END}"
FASTQ_R2="${FASTQ_DIR}/${SAMPLE}${FQ2_END}"

if [[ ! -f "${RAW_R1_GZ}" ]]; then
  echo "[错误] 缺少输入文件: ${RAW_R1_GZ}"
  exit 1
fi

if [[ ! -f "${RAW_R2_GZ}" ]]; then
  echo "[错误] 缺少输入文件: ${RAW_R2_GZ}"
  exit 1
fi

if [[ ! -f "${FASTQ_R1}" ]]; then
  echo "[解压] 生成 ${FASTQ_R1}"
  pigz -dc "${RAW_R1_GZ}" > "${FASTQ_R1}"
else
  echo "[跳过] 已存在 ${FASTQ_R1}"
fi

if [[ ! -f "${FASTQ_R2}" ]]; then
  echo "[解压] 生成 ${FASTQ_R2}"
  pigz -dc "${RAW_R2_GZ}" > "${FASTQ_R2}"
else
  echo "[跳过] 已存在 ${FASTQ_R2}"
fi

# -----------------------------
# 运行 PRISM
# 说明：
# 1. 这里显式传入 model_org_taxids.txt，绕开 PRISM 默认参数处理问题
# 2. 第一次测试先关闭 use_custom_db，减少对 sorted_accession_map.txt 的依赖
# 3. 如果后续你已经准备好 sorted_accession_map.txt，可把 use_custom_db 改成 TRUE
# -----------------------------
echo "[运行] 开始执行 PRISM"

"${RSCRIPT_BIN}" "${PRISM_ROOT}/PRISM.R" \
  --sample "${SAMPLE}" \
  --data_path "${FASTQ_DIR}" \
  --kraken_path "${KRAKEN2_BIN}" \
  --kraken_db_path "${KRAKEN_DB}" \
  --seqkit_path "${SEQKIT_BIN}" \
  --minimap2_path "${MINIMAP2_BIN}" \
  --minimap2_index "${MINIMAP2_INDEX}" \
  --star_path "${STAR_BIN}" \
  --star_genome_dir "${STAR_GENOME_DIR}" \
  --model_org_taxids "${PRISM_ROOT}/model_org_taxids.txt" \
  --blast_path "${BLAST_BIN_DIR}" \
  --blast_db_path "${BLAST_DB}" \
  --prism_path "${PRISM_ROOT}" \
  --paired TRUE \
  --fq1_end "${FQ1_END}" \
  --fq2_end "${FQ2_END}" \
  --threads 16 \
  --use_custom_db FALSE

echo "[完成] PRISM 运行结束"
echo "[结果] 主输出目录: ${FASTQ_DIR}/${SAMPLE}_prism"
echo "[结果] 物种汇总文件: ${FASTQ_DIR}/${SAMPLE}_prism/${SAMPLE}-counts.csv"
echo "[结果] read 级结果文件: ${FASTQ_DIR}/${SAMPLE}_prism/${SAMPLE}-results.csv"
echo "[结果] 日志文件: ${FASTQ_DIR}/${SAMPLE}_prism/data/${SAMPLE}_PRISM.log"
echo "[结果] 最终微生物 FASTA: ${FASTQ_DIR}/${SAMPLE}_prism/${SAMPLE}_1.fa"
echo "[说明] 当前使用的 Kraken2 数据库: ${KRAKEN_DB}"
echo "[说明] 当前使用的 BLAST 数据库: ${BLAST_DB}"
echo "[说明] 当前使用的 Minimap2 索引: ${MINIMAP2_INDEX}"
echo "[说明] 当前使用的 STAR genomeDir: ${STAR_GENOME_DIR}"
echo "[说明] 当前推断的 PROJECT_ROOT: ${PROJECT_ROOT}"
