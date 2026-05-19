#!/usr/bin/env bash

# 用途：
# 1. 包装旧的 download_prism_kraken2_sources.sh
# 2. 当下载因网络/SSL/远端异常中断时，自动做自检并重新运行
# 3. 依赖旧脚本内部的 `--resume` 与完成标记逻辑，继续未完成的 library
#
# 设计原则：
# 1. 不修改旧脚本
# 2. 只负责“失败后自动重试”
# 3. 通过 marker 和目录状态判断哪些库已完成、哪些需要继续
#
# 可调参数：
# - MAX_RETRIES：最大重试次数，默认 20
# - SLEEP_SECONDS：每次失败后的等待时间，默认 30 秒
# - PROJECT_ROOT：项目目录
#
# 使用方式：
#   bash ${PROJECT_ROOT}/00script/02_kraken/download_prism_kraken2_sources_retry.sh

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

MAX_RETRIES="${MAX_RETRIES:-20}"
SLEEP_SECONDS="${SLEEP_SECONDS:-30}"
BASE_SCRIPT="${PROJECT_ROOT}/00script/02_kraken/download_prism_kraken2_sources.sh"
KR_SOURCE_DIR="${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended"
MARKER_DIR="${KR_SOURCE_DIR}/.download_markers"
TAXONOMY_MARKER="${MARKER_DIR}/taxonomy.done"
LIBS=(archaea bacteria viral human UniVec_Core fungi)

if [[ ! -f "${BASE_SCRIPT}" ]]; then
  echo "[错误] 找不到基础下载脚本: ${BASE_SCRIPT}"
  exit 1
fi

mkdir -p "${KR_SOURCE_DIR}" "${MARKER_DIR}"

print_status() {
  echo "[状态] taxonomy: $([[ -f "${TAXONOMY_MARKER}" ]] && echo done || echo pending)"
  for lib in "${LIBS[@]}"; do
    lib_marker="${MARKER_DIR}/${lib}.done"
    lib_dir="${KR_SOURCE_DIR}/library/${lib}"
    if [[ -f "${lib_marker}" ]]; then
      echo "[状态] ${lib}: done"
    elif [[ -d "${lib_dir}" ]]; then
      echo "[状态] ${lib}: partial"
    else
      echo "[状态] ${lib}: pending"
    fi
  done
}

all_done() {
  [[ -f "${TAXONOMY_MARKER}" ]] || return 1
  for lib in "${LIBS[@]}"; do
    [[ -f "${MARKER_DIR}/${lib}.done" ]] || return 1
  done
  return 0
}

attempt=1
while (( attempt <= MAX_RETRIES )); do
  echo "[尝试] 第 ${attempt}/${MAX_RETRIES} 次运行 Kraken2 源数据下载"
  print_status

  if bash "${BASE_SCRIPT}"; then
    if all_done; then
      echo "[完成] 所有 Kraken2 源数据已成功下载"
      exit 0
    else
      echo "[警告] 基础脚本返回成功，但完成标记不完整，准备重试"
    fi
  else
    rc=$?
    echo "[警告] 基础脚本异常退出，返回码: ${rc}"
  fi

  if all_done; then
    echo "[完成] 虽然出现过异常，但最终所有完成标记已齐全"
    exit 0
  fi

  echo "[等待] ${SLEEP_SECONDS} 秒后自动重试"
  sleep "${SLEEP_SECONDS}"
  attempt=$(( attempt + 1 ))
done

echo "[失败] 达到最大重试次数 ${MAX_RETRIES}，仍未完成下载"
print_status
exit 1
