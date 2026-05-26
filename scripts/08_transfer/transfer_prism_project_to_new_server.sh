#!/usr/bin/env bash

# 用途：
# 1. 使用 rsync 将整个 PRISM 项目目录同步到新的服务器
# 2. 支持断点续传
# 3. 支持 dry-run 预演
#
# 使用方法：
#   bash transfer_prism_project_to_new_server.sh <源目录> <远端用户> <远端主机> <远端目录> [SSH端口] [--dry-run]
#
# 示例：
#   bash transfer_prism_project_to_new_server.sh \
#     /home/data/vip0/project/11PRISM \
#     ubuntu \
#     ssh.sxqtx.com \
#     /home/ubuntu/PRISM \
#     13569 \
#     --dry-run
#
# 再正式执行：
#   bash transfer_prism_project_to_new_server.sh \
#     /home/data/vip0/project/11PRISM \
#     ubuntu \
#     ssh.sxqtx.com \
#     /home/ubuntu/PRISM \
#     13569
#
# 参数说明：
#   $1  源目录
#   $2  远端用户名
#   $3  远端主机名或 IP
#   $4  远端目标目录
#   $5  SSH 端口（可选，默认 22）
#   $6  --dry-run（可选）

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "用法：bash $0 <源目录> <远端用户> <远端主机> <远端目录> [SSH端口] [--dry-run]"
  exit 1
fi

SRC_DIR="$1"
DEST_USER="$2"
DEST_HOST="$3"
DEST_DIR="$4"
SSH_PORT="${5:-22}"
DRY_RUN="${6:-}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "[错误] 源目录不存在: ${SRC_DIR}"
  exit 1
fi

for exe in rsync ssh; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

SSH_OPTS=(-p "${SSH_PORT}")
RSYNC_OPTS=(-aHAX --numeric-ids --info=progress2 --partial --append-verify)

echo "[检查] 目标服务器连通性"
if [[ "${DRY_RUN}" == "--dry-run" ]]; then
  echo "[DRY-RUN] 跳过实际 SSH mkdir"
else
  ssh "${SSH_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "mkdir -p '${DEST_DIR}'"
fi

echo "[同步] 源目录: ${SRC_DIR}/"
echo "[同步] 目标目录: ${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
echo "[同步] SSH 端口: ${SSH_PORT}"

if [[ "${DRY_RUN}" == "--dry-run" ]]; then
  echo "[DRY-RUN] 仅预演，不实际传输"
  printf 'rsync '
  printf '%q ' "${RSYNC_OPTS[@]}"
  printf '%q ' -e "ssh -p ${SSH_PORT}" "${SRC_DIR}/" "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
  printf '\n'
else
  rsync "${RSYNC_OPTS[@]}" \
    -e "ssh -p ${SSH_PORT}" \
    "${SRC_DIR}/" \
    "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
fi

echo "[完成] 项目目录同步结束"

