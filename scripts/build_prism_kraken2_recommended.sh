#!/usr/bin/env bash

# 用途：
# 1. 构建一个更贴近 PRISM 设定的 Kraken2 数据库
# 2. 使用官方库组件，不再自己下载“全部真菌基因组”再手工拼库
#
# 数据库组成：
# - archaea
# - bacteria
# - viral
# - human
# - UniVec_Core
# - fungi
#
# 说明：
# 1. 这是面向 PRISM 的推荐配置，不是 fungi-only 测试库
# 2. 这样更适合肿瘤 RNA-seq 中先做广义微生物筛查，再进入 PRISM 后续流程
# 3. 某些 Kraken2 版本默认使用 rsync 访问 NCBI，会出现：
#    Unknown module 'pub'
# 4. 因此这里强制使用 --use-ftp，并在 taxonomy 下载时同时加 --skip-maps
# 5. 如果你的 Kraken2 版本不支持 --use-ftp，则需要升级到较新的版本
# 6. 为减少磁盘占用，本脚本会在每个 library 下载完成后：
#    - 将 FASTA 追加到一个合并库文件
#    - 删除该 library 的原始下载目录
# 7. 这样可以减少中间文件堆积，但最终 build 期间仍需要：
#    taxonomy + 合并后的库文件 + Kraken2 构建输出

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
DB_ROOT="${PROJECT_ROOT}/02ref/kraken2"
DB_DIR="${DB_ROOT}/prism_kraken2_recommended"
KRAKEN_DOWNLOAD_OPTS="${KRAKEN_DOWNLOAD_OPTS:---use-ftp}"
LIBRARY_DIR="${DB_DIR}/library"
STAGED_LIBRARY_FASTA="${LIBRARY_DIR}/combined_standard_library.fna"
MARKER_DIR="${DB_DIR}/.download_markers"

echo "[检查] 检查 kraken2-build"
if ! command -v kraken2-build >/dev/null 2>&1; then
  echo "[错误] 未找到 kraken2-build"
  exit 1
fi

mkdir -p "${DB_ROOT}" "${DB_DIR}"
mkdir -p "${LIBRARY_DIR}" "${MARKER_DIR}"

if [[ ! -f "${STAGED_LIBRARY_FASTA}" ]]; then
  touch "${STAGED_LIBRARY_FASTA}"
fi

if [[ ! -d "${DB_DIR}/taxonomy" ]]; then
  echo "[下载] Kraken2 taxonomy"
  kraken2-build --download-taxonomy ${KRAKEN_DOWNLOAD_OPTS} --skip-maps --db "${DB_DIR}"
else
  echo "[跳过] taxonomy 已存在"
fi

for lib in archaea bacteria viral human UniVec_Core fungi; do
  marker_file="${MARKER_DIR}/${lib}.done"

  if [[ -f "${marker_file}" ]]; then
    echo "[跳过] Kraken2 library 已处理: ${lib}"
    continue
  fi

  echo "[下载] Kraken2 library: ${lib}"
  kraken2-build --download-library "${lib}" ${KRAKEN_DOWNLOAD_OPTS} --db "${DB_DIR}"

  lib_dir="${LIBRARY_DIR}/${lib}"
  if [[ ! -d "${lib_dir}" ]]; then
    echo "[错误] 下载后未找到 library 目录: ${lib_dir}"
    exit 1
  fi

  echo "[整理] 合并 ${lib} 的 FASTA 并删除原始目录"
  found_fasta=0
  while IFS= read -r -d '' fasta_file; do
    cat "${fasta_file}" >> "${STAGED_LIBRARY_FASTA}"
    found_fasta=1
  done < <(find "${lib_dir}" -type f \( -name '*.fna' -o -name '*.fa' -o -name '*.fasta' \) -print0)

  if [[ "${found_fasta}" -ne 1 ]]; then
    echo "[错误] 未在 ${lib_dir} 中找到可合并的 FASTA 文件"
    exit 1
  fi

  rm -rf "${lib_dir}"
  touch "${marker_file}"
done

echo "[构建] 开始 build"
kraken2-build --build --threads "${THREADS}" --db "${DB_DIR}"

echo "[清理] 删除中间下载文件"
kraken2-build --clean --db "${DB_DIR}"

echo "[完成] Kraken2 数据库目录:"
echo "${DB_DIR}"
echo "[说明] 当前 PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[说明] 当前 Kraken 下载参数: ${KRAKEN_DOWNLOAD_OPTS}"
