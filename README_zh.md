# PRISM 数据准备说明

## 目标

准备 PRISM 运行所需的参考资源：

1. Kraken2 分类数据库
2. BLAST `core_nt`
3. `sorted_accession_map.txt`
4. Minimap2 宿主索引
5. STAR 宿主索引
6. `genbank/` 辅助目录

## 先说明变量写法

建议你先定义项目目录变量：

```bash
export PROJECT_ROOT=/your/path/to/PRISM
```

后续文档中的 `${PROJECT_ROOT}` 才是可以直接复制执行的 shell 写法。

## 1. 环境配置

### 1.1 创建 conda 环境

```bash
conda env create -f ${PROJECT_ROOT}/00script/environment_prism.yml
conda activate prism
```

### 1.2 可选：安装 Kraken2 PR #1015 修复版

如果你希望在当前 conda 环境中安装 Kraken2 PR #1015 修复版：

#### 服务器可以直接访问 GitHub

```bash
bash ${PROJECT_ROOT}/00script/install_kraken2_pr1015.sh
```

#### 服务器不能访问 GitHub

先在能访问 GitHub 的机器上手动准备源码：

```bash
git clone git@github.com:DerrickWood/kraken2.git
cd kraken2
git fetch origin pull/1015/head:pr1015
git checkout pr1015
cd ..
tar -czf kraken2-pr1015-src.tar.gz kraken2
```

把压缩包上传到服务器，建议放到：

```bash
${PROJECT_ROOT}/02ref/src/kraken2-pr1015-src.tar.gz
```

然后在服务器上执行：

```bash
bash ${PROJECT_ROOT}/00script/install_kraken2_pr1015_offline.sh
```

说明：

- 数据库下载/构建阶段可以使用 `k2`
- 后续 PRISM 分析仍旧继续调用 `kraken2`

## 2. Kraken2 数据库

### 2.1 下载机

```bash
bash ${PROJECT_ROOT}/00script/download_prism_kraken2_sources.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended
```

### 2.2 服务器

把源数据目录复制到服务器同路径后：

```bash
bash ${PROJECT_ROOT}/00script/build_prism_kraken2_recommended.sh
```

最终数据库目录：

```bash
${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
```

## 3. BLAST core_nt

### 3.1 下载机

```bash
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt_sources.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/blast_sources/core_nt
```

### 3.2 服务器

把源数据目录复制到服务器同路径后：

```bash
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt.sh
```

最终会生成并复制：

```bash
${PROJECT_ROOT}/00script/repo/sorted_accession_map.txt
```

## 4. 宿主索引

### 4.1 下载机

```bash
bash ${PROJECT_ROOT}/00script/download_prism_host_reference.sh
```

宿主源数据目录：

```bash
${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq
```

### 4.2 服务器

把宿主源数据目录复制到服务器同路径后：

```bash
bash ${PROJECT_ROOT}/00script/build_prism_host_indexes.sh
```

默认输出目录：

```bash
${PROJECT_ROOT}/02ref/host
```

## 5. genbank 目录

需要手动把 PRISM 的 `genbank/` 目录放到：

```bash
${PROJECT_ROOT}/00script/repo/genbank
```

## 6. 检查资源是否齐全

```bash
bash ${PROJECT_ROOT}/00script/check_prism_required_data.sh
```

## 7. 推荐执行顺序

```bash
export PROJECT_ROOT=/your/path/to/PRISM
conda env create -f ${PROJECT_ROOT}/00script/environment_prism.yml
conda activate prism

# 可选：如果需要，先安装 Kraken2 PR #1015 修复版
# bash ${PROJECT_ROOT}/00script/install_kraken2_pr1015.sh

# 下载机上执行
bash ${PROJECT_ROOT}/00script/download_prism_kraken2_sources.sh
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt_sources.sh
bash ${PROJECT_ROOT}/00script/download_prism_host_reference.sh

# 把以下目录复制到服务器同路径
# ${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended
# ${PROJECT_ROOT}/02ref/blast_sources/core_nt
# ${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq

# 服务器上执行
bash ${PROJECT_ROOT}/00script/build_prism_kraken2_recommended.sh
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt.sh
bash ${PROJECT_ROOT}/00script/build_prism_host_indexes.sh
bash ${PROJECT_ROOT}/00script/check_prism_required_data.sh
```

## 8. 注意事项

1. `core_nt` 很大，下载和磁盘占用都不小。
2. Kraken2、BLAST、宿主索引都建议分成“下载机”和“服务器构建机”两段式。
3. `PRISM.R` 当前对 `model_org_taxids` 默认值处理有问题，运行时务必显式传：

```bash
--model_org_taxids ${PROJECT_ROOT}/00script/repo/model_org_taxids.txt
```

