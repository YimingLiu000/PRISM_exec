# PRISM 结果文件说明

本文以 `result/FUSCCTNBC091_prism` 作为一个已经运行完成的经典样本结果目录，说明 PRISM 每个输出文件的含义和主要内容。实际运行时，文件名前缀 `FUSCCTNBC091` 可替换为任意样本名，即 `<sample>`。

## 目录总体结构

一个样本完成后，典型目录如下：

```text
<sample>_prism/
├── <sample>-counts.csv
├── <sample>-results.csv
├── <sample>.prism.log
├── <sample>_1.fa
├── <sample>_2.fa
└── data/
    ├── <sample>.kraken.output.txt
    ├── <sample>.kraken.report.txt
    ├── <sample>.kraken.report.std.txt
    ├── <sample>.kraken.report.mpa.txt
    ├── <sample>.mpa.prism.txt
    ├── <sample>_1.fa
    ├── <sample>_2.fa
    ├── <sample>-minimap.sam
    ├── star/
    ├── <sample>_sub_fa1
    ├── <sample>_sub_fa2
    ├── <sample>_sub_fa1-blast.csv
    ├── <sample>_sub_fa2-blast.csv
    ├── <sample>-final-blast1.csv
    ├── <sample>-final-blast2.csv
    ├── <sample>-filtered-blast.csv
    ├── <sample>-unmapped.csv
    ├── <sample>-xgmat.csv
    ├── <sample>.tempout.txt
    └── <sample>_PRISM.log
```

顶层目录中的 `counts.csv`、`results.csv` 和最终 FASTA 是主要交付结果。`data/` 目录保存流水线中间文件、质控/比对日志和便于断点续跑的缓存文件。

## 顶层最终结果

### `<sample>-counts.csv`

物种级别的最终汇总表，是最常用的结果文件之一。每一行代表一个 PRISM 最终保留的物种。

主要列：

| 列名 | 含义 |
| --- | --- |
| `tax_name` | 物种学名 |
| `staxids` | NCBI taxonomy ID |
| `n` | 最终支持该物种的 reads 数 |
| `pred` | PRISM 预测分数，越接近 1 越像真实存在，越接近 0 越像污染或假阳性 |

示例中可看到 `Bacteroides ovatus`、`Escherichia coli`、`Cystobasidium slooffiae` 等物种及其支持 reads 数和 PRISM 分数。做微生物或真菌筛选时，通常优先查看此文件。

### `<sample>-results.csv`

read 级别的最终结果表。每一行通常对应一个最终保留 read 的一个 BLAST/注释结果，包含分类、比对、GenBank 注释和 PRISM 分数。

主要列：

| 列名 | 含义 |
| --- | --- |
| `id` | read ID |
| `read` | paired-end 中 read 方向，通常为 `1` 或 `2` |
| `staxids` | 命中的 NCBI taxonomy ID |
| `tax_name` | 对应分类名称 |
| `rank` | 分类层级，常见如 `S`/`s` 表示 species |
| `sacc` | BLAST subject accession |
| `gene` | GenBank gene 注释，可能为空 |
| `product` | GenBank product 注释，可能为空 |
| `pos` | BLAST 命中在 subject 上的位置 |
| `qcovs` | BLAST query coverage 百分比 |
| `pident` | BLAST percent identity |
| `bitscore` | BLAST bit score |
| `pred` | 该 read 所属物种的 PRISM 预测分数 |

如果需要追溯某个物种由哪些 reads 支持，或查看这些 reads 命中了哪些 accession、gene/product 注释，应查看此文件。

### `<sample>_1.fa` / `<sample>_2.fa`

最终保留下来的 PRISM 微生物 reads FASTA 文件。paired-end 样本通常有 `_1.fa` 和 `_2.fa` 两个文件。

这些文件只包含经过 Kraken2 初筛、Minimap2/STAR 宿主去除、BLAST 过滤和 PRISM 判定后保留下来的 reads。FASTA header 会被 PRISM 改写，常见格式包括原始 read ID、Kraken taxid、`PRISM` 标记、最终 `staxids` 和 BLAST `sacc`，例如：

```text
>read_id kraken:taxid|... | PRISM | staxids:28116 sacc:CP012938
SEQUENCE
```

这些 FASTA 适合用于后续人工复核、再次比对、提取真菌 reads 或做可视化。

### `<sample>.prism.log`

外层运行脚本的日志。示例中为 `FUSCCTNBC091.prism.log`。

内容包括：

- 样本名、项目路径、PRISM 源码路径等运行配置
- FASTQ 是否已存在、是否跳过解压
- 调用 PRISM 主流程的时间
- R 包 warning
- Kraken2、Minimap2、STAR、BLAST、GenBank annotation、PRISM profiling 等步骤的开始/结束时间
- 外部工具输出摘要，例如 Kraken2 classified/unclassified reads 数、Minimap2 命令和资源占用、STAR 运行摘要
- 如果某一步失败，也会记录错误信息

这个日志用于排查端到端运行是否成功。若顶层最终结果不完整，首先查看它。

## `data/` 目录中的中间文件

### `<sample>_PRISM.log`

PRISM R 主流程自己的日志。它比外层 `<sample>.prism.log` 更聚焦于 PRISM 内部步骤。

内容包括：

- `Starting PRISM pipeline`
- 每个步骤是否执行或因输出已存在而跳过
- `Filtering non-microbial reads`
- `GenBank annotation`
- `PRISM profiling`
- `Saving outputs`
- `Generating FASTA`
- 成功完成或失败信息

这个文件适合判断 PRISM 内部是从哪一步开始续跑、哪一步真正重新执行。

### `<sample>.kraken.output.txt`

Kraken2 的 read 级原始分类输出，通常非常大。每一行对应一个 read 或 read pair 的 Kraken2 分类结果。

常见字段包括：

| 字段 | 含义 |
| --- | --- |
| 第 1 列 | `C` 表示 classified，`U` 表示 unclassified |
| 第 2 列 | read ID |
| 第 3 列 | Kraken2 分配的 taxon name 和 taxid |
| 第 4 列 | read 长度，paired-end 中可见类似 `150|150` |
| 第 5 列 | k-mer / minimizer 层面的分类路径信息 |

PRISM 后续会从此文件中提取候选微生物 reads，并在 profiling 阶段再次用它计算 k-mer taxonomy 相关特征。

### `<sample>.kraken.report.txt`

Kraken2 的层级分类报告。它按 taxonomy tree 展示不同层级的 reads 数、唯一 minimizer 数和 taxid。

示例中的列数比标准 Kraken2 report 更多，因为运行时使用了 `--report-minimizer-data`。常见信息包括：

- 当前分类节点占总 reads 的比例
- 当前节点及其子节点的 reads 数
- 直接分配到当前节点的 reads 数
- minimizer/k-mer 相关计数
- taxonomy rank，例如 `R`、`D`、`K`、`P`、`C`、`O`、`F`、`G`、`S`
- NCBI taxid
- 分类名称

PRISM 用它确定候选微生物 taxid、物种层级、reads 丰度和部分模型特征。

### `<sample>.kraken.report.std.txt`

从 `<sample>.kraken.report.txt` 裁剪出的简化版 Kraken report。代码中通过 `cut -f1-3,6-8` 生成，只保留转换 MPA 格式所需的关键列。

它主要是给 `kreport2mpa.py` 使用的中间文件，一般不需要人工查看。

### `<sample>.kraken.report.mpa.txt`

由 `kreport2mpa.py` 从标准 Kraken report 转换得到的 MPA/MetaPhlAn 风格分类谱。

内容通常是：

```text
taxonomic_path    count
```

其中 `taxonomic_path` 类似 `k__Bacteria|p__...|s__...`。PRISM 用这个文件更方便地按谱系识别 Bacteria、Fungi、Viruses 等微生物分支。

### `<sample>.mpa.prism.txt`

PRISM 在 MPA 风格结果基础上进一步加工得到的内部分类谱文件。

主要列：

| 列名 | 含义 |
| --- | --- |
| `V1` | MPA 风格 taxonomy path |
| `V2` | 对应 reads/count 数 |
| `taxid` | PRISM 补充的 taxonomy lineage taxid 链，常用 `*taxid*taxid*` 形式 |

后续的微生物筛选、谱系追踪和模型特征构造会用到这个文件。

### `data/<sample>_1.fa` / `data/<sample>_2.fa`

PRISM 中间过程中的候选 reads FASTA。它们由 Kraken2 classified-out 结果和后续宿主去除步骤生成、覆盖更新。

流程含义：

1. Kraken2 初筛后提取候选微生物 reads。
2. Minimap2 去除能比对到宿主基因组的 reads。
3. STAR 再做一轮宿主去除。
4. 过滤后的中间 FASTA 保存在 `data/` 里供 BLAST 使用。

注意：`data/` 下的 `_1.fa`/`_2.fa` 是中间候选 reads；顶层 `_1.fa`/`_2.fa` 是最终 PRISM 保留 reads。

### `<sample>-minimap.sam`

Minimap2 对候选 reads 进行宿主基因组比对后的 SAM 文件。

用途：

- 判断候选 reads 是否能比对到宿主参考基因组
- PRISM 读取 SAM flag，保留 unmapped reads，去掉 host-mapped reads

文件可能很大。人工排查时主要看 SAM header、FLAG、RNAME、POS、MAPQ 等标准 SAM 字段。

### `star/<sample>_Aligned.out.sam`

STAR 对 Minimap2 过滤后 reads 再做宿主比对产生的 SAM 文件。

PRISM 用它识别仍可比对到宿主基因组的 reads，并从中间 FASTA 里移除这些 reads。它是第二轮宿主去除的核心输出。

### `star/<sample>_Log.final.out`

STAR 的最终运行统计摘要。适合快速查看 STAR 宿主去除阶段的结果。

常见信息包括：

- input reads 数
- average read length
- uniquely mapped reads 数和比例
- multi-mapping reads 数和比例
- unmapped reads 数和原因
- mismatch、insertion、deletion 等比对质量统计

如果怀疑宿主去除过强或过弱，优先查看此文件。

### `star/<sample>_Log.out`

STAR 的完整运行日志。包含 STAR 版本、参数、genomeDir、加载 genome、mapping、完成时间等详细信息。

用于排查 STAR 参数、索引路径和运行错误。

### `star/<sample>_Log.progress.out`

STAR 运行过程中的进度日志。内容通常较短，记录 mapping 过程的进展状态。

用于观察长任务是否仍在推进，或回看运行过程。

### `star/<sample>_SJ.out.tab`

STAR 输出的 splice junction 表。对 RNA-seq 数据来说，它记录 STAR 识别到的剪接位点。

常见列包括染色体、intron 起止位置、strand、motif、是否注释剪接、unique/multi-mapping 支持 reads 数、最大 overhang 等。

在 PRISM 流程中，它主要是 STAR 的附带输出；微生物判定通常不直接依赖它。

### `<sample>_sub_fa1` / `<sample>_sub_fa2`

按 taxid 下采样后的候选微生物 reads FASTA。PRISM 会对每个候选物种抽取一定数量 reads，用于快速 BLAST 和 multi-mapping 分析。

用途：

- 降低第一次 BLAST 的计算量
- 判断哪些物种拥有足够“可唯一识别”的 reads
- 为后续 full BLAST 选择目标 taxid

这些文件没有 `.fa` 后缀，但内容仍是 FASTA。

### `<sample>_sub_fa1-blast.csv` / `<sample>_sub_fa2-blast.csv`

下采样 FASTA 的 BLAST 输出，read1 和 read2 分别保存。

PRISM 的 BLAST 输出使用 CSV 分隔，但没有表头。列顺序为：

| 列序号 | 含义 |
| --- | --- |
| 1 | `qseqid`，query/read ID |
| 2 | `sacc`，subject accession |
| 3 | `staxids`，subject taxid |
| 4 | `sstart`，subject 起始位置 |
| 5 | `qcovs`，query coverage |
| 6 | `pident`，percent identity |
| 7 | `bitscore` |

这些文件用于 `prism_multimapping()`，帮助判断候选物种是否具有唯一可识别 reads。

### `<sample>-final-blast1.csv` / `<sample>-final-blast2.csv`

full BLAST 输出。与下采样 BLAST 相比，它针对经过筛选的完整候选 reads 集合运行，并限制到人源、常见模式生物以及 multi-mapping 分析确认的目标微生物 taxid。

同样没有表头，列顺序为：

| 列序号 | 含义 |
| --- | --- |
| 1 | `qseqid` |
| 2 | `sacc` |
| 3 | `staxids` |
| 4 | `sstart` |
| 5 | `qcovs` |
| 6 | `pident` |
| 7 | `bitscore` |

后续 `<sample>-filtered-blast.csv`、`<sample>-unmapped.csv`、`<sample>-results.csv` 都由这些 full BLAST 结果进一步过滤、注释和打分得到。

### `<sample>-filtered-blast.csv`

从 full BLAST 结果中过滤出的高质量微生物命中表，已经带有表头。

主要列：

| 列名 | 含义 |
| --- | --- |
| `id` | read ID |
| `read` | read 方向，`1` 或 `2` |
| `rank` | PRISM/Kraken taxonomy rank |
| `staxids` | 微生物 taxid |
| `tax_name` | 分类名称 |
| `sacc` | BLAST accession |
| `pos` | subject 起始位置 |
| `qcovs` | query coverage |
| `pident` | percent identity |
| `bitscore` | BLAST bit score |

这个文件是进入 GenBank 注释和 PRISM profiling 的主要 BLAST 过滤结果。它还没有 `gene`、`product` 和 `pred`，这些会在后续生成顶层 `<sample>-results.csv`。

### `<sample>-unmapped.csv`

被过滤掉、不进入最终微生物结果的 BLAST 命中记录。

主要列：

| 列名 | 含义 |
| --- | --- |
| `id` | read ID |
| `read` | read 方向 |
| `staxids` | 命中 taxid |
| `type` | 被排除原因 |
| `sacc` | BLAST accession |
| `pos` | subject 起始位置 |
| `qcovs` | query coverage |
| `pident` | percent identity |
| `bitscore` | BLAST bit score |

`type` 常见值：

| 值 | 含义 |
| --- | --- |
| `human` | 命中人源 taxid，例如 9606 |
| `other` | 高质量但不属于 PRISM 目标微生物分支 |
| `lowqual` | BLAST 质量不足 |

该文件用于解释为什么某些 reads 没有进入最终结果。

### `<sample>-xgmat.csv`

PRISM XGBoost 模型使用的物种级特征矩阵。每一行对应一个候选 taxid。

常见特征包括：

- `fprod`、`fugene`、`fuprod`：GenBank gene/product 注释相关比例
- `prod_div`、`gene_div`：product/gene 多样性
- `ratio`、`sacc_ratio4`、`sacc_ratio5`：multi-mapping 和 accession 分布相关特征
- `unclassified`、`host`、`unrelated`：Kraken k-mer 误分类/来源比例
- `k`、`p`、`c`、`o`、`f`、`g`、`s` 及对应 `_n`、`_r`、`_u`：不同分类层级上的 Kraken/MPA 谱系特征
- `n2`、`n3`、`uniq`：Kraken report 中的 species 计数和唯一性指标
- `fmicro`、`fcontam`：微生物丰度和污染参考 taxid 相关比例

这个文件不是最终报告，但对理解 `pred` 是如何由特征推断出来很有帮助。

### `<sample>.tempout.txt`

PRISM profiling 阶段生成的临时文件。它从 `<sample>.kraken.output.txt` 中筛出与最终候选 taxid 相关的 Kraken2 原始 read 级记录。

用途：

- 供 `prism_misclass_kmertax()` 计算 k-mer taxonomy/misclassification 特征
- 生成 `<sample>-xgmat.csv` 的部分输入

如果只是查看最终物种结果，通常不需要看它。

## 如何优先查看这些文件

如果目标是快速理解样本中有哪些可信微生物：

1. 先看 `<sample>-counts.csv`：按物种查看 `n` 和 `pred`。
2. 再看 `<sample>-results.csv`：追溯具体 reads、accession、gene/product 注释。
3. 必要时看顶层 `<sample>_1.fa` / `<sample>_2.fa`：提取最终 reads。

如果目标是排查流程：

1. 先看 `<sample>.prism.log` 和 `data/<sample>_PRISM.log`。
2. Kraken2 问题看 `data/<sample>.kraken.report.txt` 和 `data/<sample>.kraken.output.txt`。
3. 宿主去除问题看 `data/<sample>-minimap.sam` 和 `data/star/<sample>_Log.final.out`。
4. BLAST/过滤问题看 `data/<sample>-final-blast*.csv`、`data/<sample>-filtered-blast.csv` 和 `data/<sample>-unmapped.csv`。
5. PRISM 分数问题看 `data/<sample>-xgmat.csv`。

