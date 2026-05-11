# PRISM 论文方法学解读与算法说明

## 概述

本文档基于以下两部分内容整理：

1. `paper.pdf` 中可提取的论文方法学相关内容，重点包括：
   - `STAR Methods`
   - `Method details`
   - `PRISM algorithm`
   - `Overview`
2. 仓库源码实现：
   - `PRISM.R`
   - `functions.R`

目标是解释 `PRISM` 的算法原理、输入和输出，并说明它在 RNA-seq 微生物检测中的实际含义。

## PRISM 想解决的问题

`PRISM` 不是一个单纯的“微生物分类器”，而是一个用于低生物量肿瘤测序数据的高置信微生物识别框架。

它主要要解决以下问题：

1. 宿主序列去除不彻底  
   人源 reads 数量远高于微生物 reads，残留宿主序列很容易造成假阳性。

2. 快速分类器的误分类  
   仅依赖 `Kraken2` 这类 k-mer 分类器时，read 容易被归到近缘但并不真实存在的物种。

3. 微生物 reads 的多重比对  
   很多物种之间序列相似度高，一个 read 可能同时匹配多个物种。

4. 低生物量样本中的污染  
   在肿瘤 RNA-seq 中，真实微生物信号通常很弱，污染和背景信号可能更显著。

因此，`PRISM` 的重点不是“尽可能多地报出微生物”，而是“尽可能可靠地区分真实存在的微生物与污染或误分类结果”。

## 算法的总体思想

从论文方法学和代码实现看，`PRISM` 的设计可以概括为三层：

1. 宿主去除  
2. 精细重分类与唯一性约束  
3. 基于特征的机器学习污染判别

也就是说，它并不是一步到位的模型，而是一个“规则化过滤 + 精细比对 + 监督学习打分”的组合框架。

最终输出的核心不是简单的 read count，而是一个 `PRISM score`，表示某个物种更像“真实存在”而不是“污染/伪阳性”的概率。

## PRISM 的核心流程

主流程写在 `PRISM.R` 中，源码把流程拆成 12 步。

### 第一阶段：初筛与宿主去除

#### 1. Kraken2 初筛

先对原始测序数据进行快速分类，找出候选微生物 reads。

实现函数：

- `prism_kraken()`

该步骤的作用不是得到最终结果，而是快速锁定“可能是微生物”的 reads。

#### 2. Minimap2 去宿主

将候选微生物 reads 比对到宿主参考基因组，去掉仍可比到宿主的 reads。

实现函数：

- `prism_minimap()`

#### 3. STAR 再去宿主

使用第二种宿主比对工具再过滤一轮宿主 reads。

实现函数：

- `prism_star()`

这三步结合起来的思想是：

- 先宽松抓取候选微生物 reads
- 再用多种方法尽可能清除残留宿主信号

## 第二阶段：唯一性与物种可识别性分析

#### 4. 按 taxid 下采样

对每个候选 taxid 抽取有限数量 reads，用于后续精细判别。

实现函数：

- `prism_subsample()`

这样做的目的是降低后续 BLAST 分析的计算量，同时保留每个物种的代表性 reads。

#### 5. 对下采样 reads 做 BLAST

对候选物种代表性 reads 做更精确的序列比对。

实现函数：

- `prism_blast()`，`mode = 'subsample'`

#### 6. 多重比对分析，筛选“唯一可识别物种”

这是 PRISM 的关键设计之一。

实现函数：

- `prism_multimapping()`

其核心思想是：

- 某个物种要被保留，必须有足够多的 `uniquely mappable reads`
- 如果 reads 同时稳定匹配多个近缘物种，则该物种不够“可识别”

这意味着 PRISM 更关注“高置信唯一支持”的物种，而不是接受所有有一些匹配证据的微生物。

这是提高特异性的核心策略之一。

### 第三阶段：全量精比对与规则过滤

#### 7. 对完整 reads 集合做正式 BLAST

一旦某物种通过了唯一性约束，就回到完整数据，对该样本剩余 reads 做正式 BLAST 分析。

实现函数：

- `prism_blast()`，`mode = 'full'`

#### 8. 过滤人源、低质量和非微生物命中

实现函数：

- `prism_filter()`

这一步会：

- 去除 human 命中
- 去除低覆盖度或低可信度命中
- 去除非微生物命中
- 为每个 read 选择较优的微生物解释

这一步的结果可以看作是一个高质量的 read-level microbial table。

### 第四阶段：功能注释与监督学习打分

#### 9. 加入 GenBank 注释

实现函数：

- `prism_genbank()`

PRISM 会根据 BLAST 命中的 accession 和位置，把 reads 映射到 GenBank 的 gene / product 注释上。

这样每个 read 不仅有 taxon 信息，还有功能注释信息。

#### 10. 构建特征并进入 XGBoost 模型

实现函数：

- `prism_profile()`

这是 PRISM 的第二个核心环节。  
在前面已经做完规则过滤和重分类之后，PRISM 还会为每个物种提取多种统计特征，再输入一个预训练的 `XGBoost` 模型，输出 `PRISM score`。

这个分数表示：

- 某个物种更像“真实存在信号”还是“污染/伪阳性信号”

#### 11. 保存结果

保存：

- `results.csv`
- `counts.csv`
- 中间特征矩阵

#### 12. 输出最终微生物 FASTA

实现函数：

- `prism_FASTA()`

输出最终保留的微生物 reads FASTA 文件。

## PRISM 的真正算法核心

如果只提炼思想，PRISM 的核心可概括为：

### 第一层：多轮宿主去除

通过 `Kraken2` 初筛后，再利用 `Minimap2` 和 `STAR` 反复清除宿主背景，降低“宿主 reads 冒充微生物”的风险。

### 第二层：唯一性约束

PRISM 不直接接受快速分类器的所有物种结果，而是要求物种必须具备足够的唯一支持 reads。

这使它在高同源微生物之间更加保守，也更强调物种识别的可解释性。

### 第三层：监督学习判别污染

即使 read 层面看上去像微生物，PRISM 仍然进一步判断：

- 这个物种的整体特征更像真实存在，还是更像污染

因此，PRISM 最终输出的是“高可信物种概率”，而不是单一工具的原始分类结果。

## PRISM 使用了哪些特征

从代码实现可知，PRISM 至少整合了 5 类特征。

### 1. GenBank 注释多样性特征

实现函数：

- `prism_genbank_stats()`

包括：

- 基因数量
- 产物数量
- 基因/产物多样性

这些特征用于判断一个物种的 read 命中是否具有功能层面的丰富性和一致性。

### 2. 多重比对特征

实现函数：

- `prism_multimapping_ratios()`

包括：

- 某物种 reads 中多重比对的比例
- accession 在 unique-hit 与 multi-hit 之间的重叠关系

这些特征用于衡量该物种是否容易被近缘物种混淆。

### 3. k-mer 分类学信号特征

实现函数：

- `prism_misclass_kmertax()`

它会回看 Kraken 风格输出，统计候选物种相关 reads 的 k-mer 信号分布在：

- kingdom
- phylum
- class
- order
- family
- genus
- species
- unclassified
- host
- unrelated

这些信号反映分类支持是否自洽。

### 4. 分类层级一致性 / 误分类特征

同样来自：

- `prism_misclass_kmertax()`

这类特征关注：

- 一个物种在不同 taxonomy rank 上的信号是否稳定
- 是否更像一个谱系一致的真实物种，而不是分类噪音

### 5. Kraken 计数特征

实现函数：

- `prism_krcounts()`

包括：

- Kraken 中的 read 数
- unique k-mer 数
- 相对于微生物总量的比例
- 相对于一些常见污染物的比例

这些特征帮助模型判断该物种是否呈现“真实信号”的丰度模式。

## 输入是什么

从 `PRISM.R` 看，输入分为三类。

### 1. 样本输入

- 单端或双端 FASTQ / FASTA
- 样本名 `--sample`
- 数据目录 `--data_path`

### 2. 外部工具

- `Kraken2`
- `SeqKit`
- `Minimap2`
- `STAR`
- `BLAST+`

### 3. 参考数据库与辅助资源

- `Kraken2` 数据库
- `Minimap2` 宿主 `.mmi`
- `STAR genomeDir`
- `BLAST` 数据库
- `model_org_taxids.txt`
- `genbank/`
- `sorted_accession_map.txt`

此外还有流程控制参数，例如：

- `paired`
- `min_read_per`
- `min_uniq_frac`
- `max_sample`
- `min_qcovs`
- `threads`
- `use_custom_db`

## 输出是什么

PRISM 的最终输出主要有三类。

### 1. `X-results.csv`

read 级别最终结果。

常见列包括：

- `id`
- `read`
- `staxids`
- `tax_name`
- `rank`
- `sacc`
- `gene`
- `product`
- `qcovs`
- `pident`
- `bitscore`
- `pred`

其中 `pred` 是 read 所属物种的 PRISM score。

### 2. `X-counts.csv`

物种级别汇总结果。

常见列包括：

- `tax_name`
- `staxids`
- `n`
- `pred`

其中：

- `n`：支持该物种的 reads 数
- `pred`：该物种是真实存在而非污染的概率

### 3. `X_1.fa` / `X_2.fa`

最终保留下来的微生物 reads FASTA 文件。

## 对 RNA-seq 微生物 / 真菌分析的实际意义

如果你的目标是从 RNA-seq 中识别真菌，PRISM 的定位应该理解为：

1. 先在 RNA-seq 中识别“高可信微生物信号”
2. 再从这些结果里提取真菌物种

也就是说，PRISM 本身不是“真菌专用算法”，而是“广义微生物高可信识别算法”。

对真菌分析来说，你真正关心的是：

- 真菌物种的 `n`
- 真菌物种的 `pred`

含义分别是：

- `n`：PRISM 最终保留的支持 reads 数
- `pred`：该真菌更像真实存在还是污染的概率

## 总结

一句话概括 `PRISM`：

`PRISM` 是一个通过多轮宿主去除、唯一性约束、全量精比对和监督学习打分来识别低生物量测序数据中真实微生物物种的高置信分析框架。

对 RNA-seq 应用来说，它的优势不在于“报得多”，而在于：

- 更强调真实性
- 更强调可解释性
- 更强调从污染和误分类中恢复高可信微生物信号

