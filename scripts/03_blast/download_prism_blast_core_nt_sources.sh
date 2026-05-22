#!/usr/bin/env bash

# 用途：
# 1. 并行下载 NCBI BLAST 数据库 core_nt 的分卷源文件
# 2. 下载 taxdb
# 3. 校验 md5
# 4. 自动并行解压到下游分析所需的标准目录
#
# 说明：
# 1. 该脚本使用 aria2c 并行下载 core_nt.*.tar.gz 和 taxdb.tar.gz
# 2. 下载后的最终数据库目录会统一落到：
#    ${PROJECT_ROOT}/02ref/blast/core_nt
# 3. 因此下游分析脚本中的：
#    BLAST_DB=${PROJECT_ROOT}/02ref/blast/core_nt/core_nt
#    不需要修改
# 4. 分卷归档文件会保存在：
#    ${PROJECT_ROOT}/02ref/blast_sources/core_nt_archives

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

BASE_URL="${BASE_URL:-https://ftp.ncbi.nlm.nih.gov/blast/db}"
DB_NAME="core_nt"
ARCHIVE_DIR="${PROJECT_ROOT}/02ref/blast_sources/core_nt_archives"
FINAL_DIR="${PROJECT_ROOT}/02ref/blast/core_nt"
ARIA2_SPLITS="${ARIA2_SPLITS:-16}"
ARIA2_CONCURRENT="${ARIA2_CONCURRENT:-8}"
MAX_RETRIES="${MAX_RETRIES:-20}"
MARKER_DIR="${ARCHIVE_DIR}/.unpack_markers"
CLEAN_ARCHIVES_AFTER_UNPACK="${CLEAN_ARCHIVES_AFTER_UNPACK:-false}"

echo "[检查] 依赖程序"
for exe in aria2c curl grep sort awk md5sum tar pigz; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

mkdir -p "${ARCHIVE_DIR}" "${FINAL_DIR}" "${MARKER_DIR}"

INDEX_HTML="$(mktemp)"
URL_LIST="$(mktemp)"

echo "[获取] 读取远端目录索引"
curl -k -fsSL "${BASE_URL}/" > "${INDEX_HTML}"

mapfile -t VOLUMES < <(grep -oE "${DB_NAME}\.[0-9]+\.tar\.gz" "${INDEX_HTML}" | sort -Vu)
rm -f "${INDEX_HTML}"

if [[ ${#VOLUMES[@]} -eq 0 ]]; then
  echo "[错误] 未能从 ${BASE_URL}/ 发现 ${DB_NAME} 的分卷文件"
  exit 1
fi

{
  for f in "${VOLUMES[@]}"; do
    echo "${BASE_URL}/${f}"
    echo "${BASE_URL}/${f}.md5"
  done
  echo "${BASE_URL}/taxdb.tar.gz"
  echo "${BASE_URL}/taxdb.tar.gz.md5"
} > "${URL_LIST}"

echo "[下载] 开始并行下载 core_nt 分卷和 taxdb"
aria2c \
  --continue=true \
  --check-certificate=false \
  --max-connection-per-server="${ARIA2_SPLITS}" \
  --split="${ARIA2_SPLITS}" \
  --max-concurrent-downloads="${ARIA2_CONCURRENT}" \
  --min-split-size=64M \
  --max-tries="${MAX_RETRIES}" \
  --retry-wait=5 \
  --timeout=60 \
  --connect-timeout=30 \
  --allow-overwrite=false \
  --auto-file-renaming=false \
  --file-allocation=none \
  --dir="${ARCHIVE_DIR}" \
  -i "${URL_LIST}"

rm -f "${URL_LIST}"

echo "[校验] 校验 md5"
(
  cd "${ARCHIVE_DIR}"
  for md5file in *.md5; do
    md5sum -c "${md5file}"
  done
)

echo "[解压] 开始并行解压 core_nt 分卷和 taxdb"
(
  cd "${ARCHIVE_DIR}"
  for archive in ${DB_NAME}.*.tar.gz taxdb.tar.gz; do
    [[ -f "${archive}" ]] || continue
    marker="${MARKER_DIR}/${archive}.done"
    if [[ -f "${marker}" ]]; then
      echo "[跳过] 已解压: ${archive}"
      continue
    fi
    tar -I pigz -xf "${archive}" -C "${FINAL_DIR}"
    touch "${marker}"
    if [[ "${CLEAN_ARCHIVES_AFTER_UNPACK}" == "true" ]]; then
      rm -f "${archive}" "${archive}.md5"
    fi
  done
)

if [[ ! -f "${FINAL_DIR}/${DB_NAME}.ndb" && ! -f "${FINAL_DIR}/${DB_NAME}.00.nhr" && ! -f "${FINAL_DIR}/${DB_NAME}.nhr" ]]; then
  echo "[错误] 解压完成后，未在 ${FINAL_DIR} 中发现 ${DB_NAME} 的数据库前缀文件"
  exit 1
fi

echo "[完成] BLAST core_nt 已下载、校验并解压"
echo "[结果] 归档目录: ${ARCHIVE_DIR}"
echo "[结果] 数据库目录: ${FINAL_DIR}"

