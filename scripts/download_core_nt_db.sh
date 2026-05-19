#!/usr/bin/env bash

# 用途：
# 1. 在服务器上并行下载 Kraken 官方上传的 core_nt 数据库压缩包
# 2. 支持断点续传
# 3. 下载完成后校验 gzip 与 tar 完整性，尽量避免拿到损坏文件
#
# 说明：
# 1. 这是下载脚本，不负责解压后再加工数据库
# 2. 并行下载依赖 aria2c；如果服务器没有 aria2c，请先安装
# 3. 该脚本会先尝试读取远端 Content-Length，并在下载完成后做大小校验
# 4. 最后还会执行：
#    - gzip -t
#    - tar -tzf
#    来确认归档本身可正常读取
#
# 目标数据库：
#   https://genome-idx.s3.amazonaws.com/kraken/k2_core_nt_20251015.tar.gz
#
# 推荐用法：
#   bash ${PROJECT_ROOT}/00script/03_blast/download_core_nt_db.sh
#
# 可调参数：
#   PROJECT_ROOT      项目目录
#   OUT_DIR           输出目录，默认 ${PROJECT_ROOT}/02ref/kraken2_core_nt_db
#   URL               下载链接
#   ARIA2_SPLITS      并发连接数，默认 16
#   MAX_RETRIES       重试次数，默认 20

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

URL="${URL:-https://genome-idx.s3.amazonaws.com/kraken/k2_core_nt_20251015.tar.gz}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/02ref/kraken2_core_nt_db}"
FILENAME="$(basename "${URL}")"
OUT_FILE="${OUT_DIR}/${FILENAME}"
ARIA2_SPLITS="${ARIA2_SPLITS:-16}"
MAX_RETRIES="${MAX_RETRIES:-20}"

echo "[检查] 依赖程序"
for exe in aria2c curl gzip tar awk; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

mkdir -p "${OUT_DIR}"

echo "[信息] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[信息] 输出目录: ${OUT_DIR}"
echo "[信息] 下载链接: ${URL}"
echo "[信息] 并发连接数: ${ARIA2_SPLITS}"

EXPECTED_SIZE=""
EXPECTED_SIZE="$(curl -k -fsSI "${URL}" | awk 'BEGIN{IGNORECASE=1} /^Content-Length:/ {gsub("\r","",$2); print $2; exit}' || true)"

if [[ -n "${EXPECTED_SIZE}" ]]; then
  echo "[信息] 远端文件大小（字节）: ${EXPECTED_SIZE}"
else
  echo "[警告] 未能获取远端 Content-Length，后续将只做 gzip/tar 完整性校验"
fi

echo "[下载] 开始并行下载（支持断点续传）"
aria2c \
  --continue=true \
  --check-certificate=false \
  --max-connection-per-server="${ARIA2_SPLITS}" \
  --split="${ARIA2_SPLITS}" \
  --min-split-size=64M \
  --max-tries="${MAX_RETRIES}" \
  --retry-wait=5 \
  --timeout=60 \
  --connect-timeout=30 \
  --allow-overwrite=false \
  --auto-file-renaming=false \
  --file-allocation=none \
  --dir="${OUT_DIR}" \
  --out="${FILENAME}" \
  "${URL}"

if [[ ! -f "${OUT_FILE}" ]]; then
  echo "[错误] 下载结束后未找到文件: ${OUT_FILE}"
  exit 1
fi

ACTUAL_SIZE="$(stat -c '%s' "${OUT_FILE}")"
echo "[信息] 本地文件大小（字节）: ${ACTUAL_SIZE}"

if [[ -n "${EXPECTED_SIZE}" && "${ACTUAL_SIZE}" != "${EXPECTED_SIZE}" ]]; then
  echo "[错误] 下载文件大小与远端不一致"
  echo "       远端: ${EXPECTED_SIZE}"
  echo "       本地: ${ACTUAL_SIZE}"
  exit 1
fi

echo "[校验] gzip 完整性检查"
gzip -t "${OUT_FILE}"

echo "[校验] tar 归档可读性检查"
tar -tzf "${OUT_FILE}" >/dev/null

echo "[完成] core_nt 数据库压缩包下载并校验成功"
echo "[结果] 文件路径: ${OUT_FILE}"
