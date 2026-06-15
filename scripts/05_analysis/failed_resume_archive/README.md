# PRISM 失败样本续跑归档脚本

本目录中的脚本只用于处理一次历史问题：早期 PRISM 脚本存在 taxid 解析和缓存读取问题，导致部分样本在 Kraken2、Minimap2、STAR 已完成后，后续步骤失败或生成 0 字节结果。

这些脚本仅作为本次修复和续跑留档，不建议作为常规 PRISM 分析流程使用。

## 文件说明

- `prepare_failed_prism_resume.sh`
  - 扫描包含 `<sample>_prism` 结果目录的文件夹。
  - 自动识别可续跑的失败样本，并写入 `failed_prism_resume_samples.txt`。
  - 设置 `MODE=quarantine` 时，会把损坏的下游结果文件逐个移动到样本目录内的 quarantine 文件夹。
  - 不会删除文件。

- `run_failed_prism_resume_parallel.sh`
  - 读取失败样本 TXT 文件，并行续跑这些样本。
  - 直接调用 `PRISM.R`，绕过 `run_prism_rnaseq.sh`。
  - 因此不需要原始 FASTQ 或 FASTQ.GZ 文件。
  - 启动样本前会检查 Kraken2、Minimap2、STAR 及宿主过滤后的 FASTA 是否存在，避免误启动无法续跑的样本。

## 适用目录结构

将这两个脚本复制到包含 `*_prism` 结果目录的文件夹中，例如：

```text
/home/y413569-subuser-1/PRISM/02fastq/
  prepare_failed_prism_resume.sh
  run_failed_prism_resume_parallel.sh
  FUSCCTNBC005_prism/
  FUSCCTNBC008_prism/
  ...
```

每个可续跑样本至少应保留：

```text
<sample>_prism/data/<sample>.kraken.output.txt
<sample>_prism/data/<sample>.kraken.report.txt
<sample>_prism/data/<sample>.kraken.report.std.txt
<sample>_prism/data/<sample>.kraken.report.mpa.txt
<sample>_prism/data/<sample>.mpa.prism.txt
<sample>_prism/data/<sample>-minimap.sam
<sample>_prism/data/<sample>_1.fa
<sample>_prism/data/<sample>_2.fa
<sample>_prism/data/star/<sample>_Aligned.out.sam
```

## quarantine 前后变化

执行检测命令时，脚本只生成失败样本列表，不移动任何文件：

```bash
bash prepare_failed_prism_resume.sh
```

执行 quarantine 命令时：

```bash
MODE=quarantine bash prepare_failed_prism_resume.sh
```

脚本会把以下下游产物移动到：

```text
<sample>_prism/resume_quarantine_<时间戳>/
```

会被移动的文件或目录包括：

```text
<sample>_prism/<sample>-counts.csv
<sample>_prism/<sample>-results.csv
<sample>_prism/<sample>_1.fa
<sample>_prism/<sample>_2.fa
<sample>_prism/new_headers.txt
<sample>_prism/data/<sample>_sub_fa1
<sample>_prism/data/<sample>_sub_fa2
<sample>_prism/data/<sample>_sub_fa1-blast.csv
<sample>_prism/data/<sample>_sub_fa2-blast.csv
<sample>_prism/data/<sample>-final-blast1.csv
<sample>_prism/data/<sample>-final-blast2.csv
<sample>_prism/data/<sample>-filtered-blast.csv
<sample>_prism/data/<sample>-unmapped.csv
<sample>_prism/data/<sample>-xgmat.csv
<sample>_prism/data/<sample>.tempout.txt
<sample>_prism/data/customdb/
```

移动后，样本目录中仍会保留 Kraken2、Minimap2、STAR 和宿主过滤后的 FASTA。修复后的 `PRISM.R` 会跳过这些已完成步骤，从 subsampling、BLAST、filter、profile 等下游步骤继续运行。

## 关于 `customdb/` 和 `USE_CUSTOM_DB`

如果之前运行时设置了：

```bash
export USE_CUSTOM_DB=TRUE
```

PRISM 可能在 `data/customdb/` 中生成临时 BLAST 子库。这个子库依赖当时的候选 taxid 集合；早期脚本存在 taxid 解析错误时，`customdb/` 也可能是基于错误候选集合生成的。

因此续跑前应将旧的 `data/customdb/` 一并移动到 quarantine。这样：

- `USE_CUSTOM_DB=TRUE` 时，PRISM 会根据修复后的候选 taxid 重新生成新的 custom BLAST DB。
- `USE_CUSTOM_DB=FALSE` 时，PRISM 会直接使用完整 BLAST 数据库，不会使用旧的 `customdb/`。

不建议保留旧 `customdb/` 继续跑，否则可能出现“新候选 taxid 与旧 customdb 内容不一致”的问题，导致 BLAST 结果不完整或不可靠。

## 使用方法

先激活 PRISM 环境，并进入包含 `*_prism` 结果目录的文件夹：

```bash
conda activate prism
cd /home/y413569-subuser-1/PRISM/02fastq

export PROJECT_ROOT=/home/y413569-subuser-1/PRISM
export STAR_GENOME_LOAD=NoSharedMemory
export KRAKEN2_EXTRA_OPTS=""
export PRISM_THREADS=8
export USE_CUSTOM_DB=TRUE
```

第一步，检测失败样本：

```bash
bash prepare_failed_prism_resume.sh
```

该命令会在当前目录生成：

```text
failed_prism_resume_samples.txt
```

第二步，将损坏的下游结果和旧 `customdb/` 移动到 quarantine 文件夹：

```bash
MODE=quarantine bash prepare_failed_prism_resume.sh
```

第三步，并行续跑失败样本，例如同时运行 8 个样本：

```bash
bash run_failed_prism_resume_parallel.sh failed_prism_resume_samples.txt 8
```

第二个参数是同时运行的样本数，可根据服务器 CPU、内存和 BLAST 负载调整。

## 日志和输出

续跑日志默认写入当前目录下：

```text
resume_failed_prism_logs/
```

其中包括：

```text
completed_samples.txt
failed_samples.txt
skipped_incomplete_upstream.txt
```

每个样本的详细日志也会保存在该目录中。

## 注意事项

- 使用前应确认当前服务器上的 `PRISM.R` 和 `functions.R` 已包含本次修复。
- `run_failed_prism_resume_parallel.sh` 不需要原始 FASTQ 文件。
- `prepare_failed_prism_resume.sh` 不会删除文件，只会逐个移动损坏文件到 quarantine 目录。
- 如果某个样本缺少 Kraken2、Minimap2、STAR 或 `_1.fa/_2.fa` 等上游缓存，该样本会被跳过，不会自动重跑 Kraken2。
- 这些脚本是为历史失败样本补救而写，后续正常新样本分析仍应使用常规 PRISM 运行脚本。
