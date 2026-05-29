#!/usr/bin/env bash

# 用途：
# 1. 基于已经同步到本机的 core_nt 分卷归档目录进行解压
# 2. 不负责重新下载归档
# 3. 若已解压完成则自动跳过
#
# 适用场景：
# 1. 你已经把旧服务器上的：
#    ${PROJECT_ROOT}/02ref/blast_sources/core_nt_archives
#    整体同步到新服务器
# 2. 现在只需要在新服务器上完成解压和校验
#
# 说明：
# 1. 该脚本参考 download_prism_blast_core_nt_sources.sh 的解压逻辑
# 2. 它会：
#    - 检查 core_nt 分卷和 taxdb 是否存在
#    - 校验 md5
#    - 依据完成标记跳过已解压分卷
#    - 把最终数据库解压到：
#      ${PROJECT_ROOT}/02ref/blast/core_nt
# 3. 因此下游分析脚本中的：
#    BLAST_DB=${PROJECT_ROOT}/02ref/blast/core_nt/core_nt
#    不需要修改

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

DB_NAME="core_nt"
ARCHIVE_DIR="${PROJECT_ROOT}/02ref/blast_sources/core_nt_archives"
FINAL_DIR="${PROJECT_ROOT}/02ref/blast/core_nt"
MARKER_DIR="${ARCHIVE_DIR}/.unpack_markers"
CLEAN_ARCHIVES_AFTER_UNPACK="${CLEAN_ARCHIVES_AFTER_UNPACK:-false}"

echo "[检查] 依赖程序"
for exe in grep sort awk md5sum tar pigz; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

if [[ ! -d "${ARCHIVE_DIR}" ]]; then
  echo "[错误] 未找到归档目录: ${ARCHIVE_DIR}"
  exit 1
fi

mkdir -p "${FINAL_DIR}" "${MARKER_DIR}"

mapfile -t VOLUMES < <(find "${ARCHIVE_DIR}" -maxdepth 1 -type f -name "${DB_NAME}.*.tar.gz" -printf "%f\n" | sort -V)

if [[ ${#VOLUMES[@]} -eq 0 ]]; then
  echo "[错误] 未找到 ${DB_NAME} 的分卷归档"
  exit 1
fi

if [[ ! -f "${ARCHIVE_DIR}/taxdb.tar.gz" ]]; then
  echo "[错误] 未找到 taxdb.tar.gz"
  exit 1
fi

echo "[校验] 校验 md5"
(
  cd "${ARCHIVE_DIR}"
  for md5file in *.md5; do
    [[ -f "${md5file}" ]] || continue
    md5sum -c "${md5file}"
  done
)

echo "[解压] 开始并行解压 core_nt 分卷和 taxdb"
(
  cd "${ARCHIVE_DIR}"
  for archive in "${VOLUMES[@]}" taxdb.tar.gz; do
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

echo "[完成] BLAST core_nt 已解压"
echo "[结果] 归档目录: ${ARCHIVE_DIR}"
echo "[结果] 数据库目录: ${FINAL_DIR}"

