#!/usr/bin/env bash

# 用途：
# 1. 在当前 conda 环境中，基于“手动上传到服务器”的 Kraken2 源码安装 PR #1015 修复版
# 2. 让当前环境优先使用修复版的 `k2` / `kraken2` / `kraken2-build`
#
# 这个脚本适用于：
# 1. 服务器不能直接访问 GitHub
# 2. 你可以在另一台能访问 GitHub 的机器上先下载源码，再手动上传到服务器
#
# ------------------------------------------
# 你需要手动完成的步骤（在可访问 GitHub 的机器上）
# ------------------------------------------
# 方式 A：推荐，使用 git 获取 PR #1015 的源码
#
#   git clone git@github.com:DerrickWood/kraken2.git
#   cd kraken2
#   git fetch origin pull/1015/head:pr1015
#   git checkout pr1015
#   cd ..
#   tar -czf kraken2-pr1015-src.tar.gz kraken2
#
# 然后把这个压缩包上传到服务器，建议放到：
#
#   ${PROJECT_ROOT}/02ref/src/kraken2-pr1015-src.tar.gz
#
# 方式 B：如果你不用 git，也可以在浏览器中下载“PR #1015 对应源码快照”，
# 但必须确保下载的是 PR #1015 修复版代码，而不是仓库默认分支。
#
# ------------------------------------------
# 服务器上如何使用
# ------------------------------------------
# 1. 激活 conda 环境：
#    conda activate prism
#
# 2. 运行本脚本：
#    bash ${PROJECT_ROOT}/00script/07_patch_installs/install_kraken2_pr1015_offline.sh
#
# 3. 如果你上传源码目录而不是 tar.gz，可以改用环境变量指定：
#    KRAKEN2_SRC_DIR=/your/path/to/kraken2 bash install_kraken2_pr1015_offline.sh
#
# 4. 如果你上传的是 tar.gz，但路径不是默认值，也可以指定：
#    KRAKEN2_SRC_ARCHIVE=/your/path/to/kraken2-pr1015-src.tar.gz bash install_kraken2_pr1015_offline.sh

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

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "[错误] 当前没有激活 conda 环境。请先执行: conda activate prism"
  exit 1
fi

for exe in bash make perl python tar; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

DEFAULT_ARCHIVE="${PROJECT_ROOT}/02ref/src/kraken2-pr1015-src.tar.gz"
KRAKEN2_SRC_ARCHIVE="${KRAKEN2_SRC_ARCHIVE:-${DEFAULT_ARCHIVE}}"
KRAKEN2_SRC_DIR="${KRAKEN2_SRC_DIR:-}"

WORK_ROOT="${CONDA_PREFIX}/src/kraken2-pr1015-offline"
INSTALL_ROOT="${CONDA_PREFIX}/opt/kraken2-pr1015"
ACTIVATE_DIR="${CONDA_PREFIX}/etc/conda/activate.d"
ACTIVATE_FILE="${ACTIVATE_DIR}/kraken2_pr1015.sh"

rm -rf "${WORK_ROOT}"
mkdir -p "${WORK_ROOT}"
cd "${WORK_ROOT}"

if [[ -n "${KRAKEN2_SRC_DIR}" ]]; then
  if [[ ! -d "${KRAKEN2_SRC_DIR}" ]]; then
    echo "[错误] 指定的源码目录不存在: ${KRAKEN2_SRC_DIR}"
    exit 1
  fi
  echo "[使用] 使用你指定的源码目录: ${KRAKEN2_SRC_DIR}"
  cp -a "${KRAKEN2_SRC_DIR}" ./kraken2
elif [[ -f "${KRAKEN2_SRC_ARCHIVE}" ]]; then
  echo "[解压] 使用源码压缩包: ${KRAKEN2_SRC_ARCHIVE}"
  tar -xzf "${KRAKEN2_SRC_ARCHIVE}"
else
  echo "[错误] 未找到源码目录或源码压缩包"
  echo "       默认查找压缩包路径: ${KRAKEN2_SRC_ARCHIVE}"
  echo "       你需要先手动上传 Kraken2 PR #1015 的源码。"
  exit 1
fi

if [[ ! -d "${WORK_ROOT}/kraken2" ]]; then
  echo "[错误] 解压/复制后未找到 kraken2 目录"
  exit 1
fi

cd "${WORK_ROOT}/kraken2"

echo "[安装] 安装到 ${INSTALL_ROOT}"
rm -rf "${INSTALL_ROOT}"
mkdir -p "${INSTALL_ROOT}"
./install_kraken2.sh "${INSTALL_ROOT}"

mkdir -p "${ACTIVATE_DIR}"
cat > "${ACTIVATE_FILE}" <<EOF
export PATH=${INSTALL_ROOT}:\$PATH
EOF

export PATH="${INSTALL_ROOT}:${PATH}"

echo "[完成] 已离线安装 Kraken2 PR #1015 修复版"
echo "[说明] 安装目录: ${INSTALL_ROOT}"
echo "[说明] 激活脚本: ${ACTIVATE_FILE}"
echo "[说明] 当前优先命令路径:"
which k2 || true
which kraken2 || true
which kraken2-build || true
