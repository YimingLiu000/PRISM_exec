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

后续文档中的：

```bash
${PROJECT_ROOT}
```

才是可以直接复制执行的 shell 写法。

## 1. Kraken2 数据库

### 1.1 下载机只下载源数据

```bash
bash ${PROJECT_ROOT}/00script/download_prism_kraken2_sources.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended
```

### 1.2 服务器上构建数据库

把上面的源数据目录复制到服务器同路径后，运行：

```bash
bash ${PROJECT_ROOT}/00script/build_prism_kraken2_recommended.sh
```

最终数据库目录：

```bash
${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
```

## 2. BLAST core_nt

### 2.1 下载机只下载 core_nt 源数据

```bash
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt_sources.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/blast_sources/core_nt
```

### 2.2 服务器上生成 accession map

把源数据目录复制到服务器同路径后，运行：

```bash
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt.sh
```

最终会生成并复制：

```bash
${PROJECT_ROOT}/00script/repo/sorted_accession_map.txt
```

## 3. 宿主索引

### 3.1 下载机只下载宿主源数据

```bash
bash ${PROJECT_ROOT}/00script/download_prism_host_reference.sh
```

宿主源数据目录：

```bash
${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq
```

### 3.2 服务器上构建索引

把宿主源数据目录复制到服务器同路径后，运行：

```bash
bash ${PROJECT_ROOT}/00script/build_prism_host_indexes.sh
```

默认输出目录：

```bash
${PROJECT_ROOT}/02ref/host
```

## 4. genbank 目录

需要手动把 PRISM 的 `genbank/` 目录放到：

```bash
${PROJECT_ROOT}/00script/repo/genbank
```

## 5. 检查资源是否齐全

```bash
bash ${PROJECT_ROOT}/00script/check_prism_required_data.sh
```

## 6. 推荐执行顺序

```bash
conda env create -f ${PROJECT_ROOT}/00script/environment_prism.yml
conda activate prism

# 下载机上执行
bash ${PROJECT_ROOT}/00script/download_prism_kraken2_sources.sh
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt_sources.sh
bash ${PROJECT_ROOT}/00script/download_prism_host_reference.sh

# 把 ${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended
# 把 ${PROJECT_ROOT}/02ref/blast_sources/core_nt
# 把 ${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq
# 复制到服务器同路径后执行
bash ${PROJECT_ROOT}/00script/build_prism_kraken2_recommended.sh
bash ${PROJECT_ROOT}/00script/download_prism_blast_core_nt.sh
bash ${PROJECT_ROOT}/00script/build_prism_host_indexes.sh
bash ${PROJECT_ROOT}/00script/check_prism_required_data.sh
```

## 7. 注意事项

1. `core_nt` 很大，下载和磁盘占用都不小。
2. Kraken2、BLAST、宿主索引现在都建议分成“下载机”和“服务器构建机”两段式。
3. `PRISM.R` 当前对 `model_org_taxids` 默认值处理有问题，运行时务必显式传：

```bash
--model_org_taxids ${PROJECT_ROOT}/00script/repo/model_org_taxids.txt
```

