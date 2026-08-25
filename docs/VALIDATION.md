# Validation

> Fill this in with your own numbers after the run. The structure below is what to
> report; the numbers in brackets are placeholders.

## What is being validated

The ZymoBIOMICS Microbial Community Standard (D6300) contains eight bacteria and two
yeasts at defined abundances. Because the membership is known, the resistome is
knowable: running AMRFinderPlus over each member's reference genome gives the set of
resistance genes that a perfect analysis of this sample would return.

Data: ERR3152364, Oxford Nanopore GridION, 3.49M reads, N50 5.3 kbp, released CC BY 4.0
by the Loman lab (Nicholls et al., GigaScience 2019).

Subsampled to [X] Gbp for tractability on a 16 GB machine.

## What this does and does not prove

It proves the pipeline recovers, from raw reads, what AMRFinderPlus finds in the finished
genomes of the same organisms. It does not prove those calls are biologically correct:
the truth set inherits AMRFinderPlus's database and its blind spots. This is a test of
the pipeline, not of the underlying ARG database.

Host attribution is scored at genus level, not species. Kraken2 on a metagenome-assembled
contig is more reliable at genus than at species, and claiming species-level accuracy
would overstate what the method supports.

## Assembly

| metric | value |
|---|---|
| input reads after filtering | [ ] |
| total bases | [ ] |
| contigs | [ ] |
| total assembly length | [ ] |
| N50 | [ ] |
| circular contigs | [ ] |

Expected: the eight bacteria at 12% each should assemble into near-complete chromosomes
at this depth. The two yeasts at 2% each will be fragmentary.

## Gene recovery

| metric | value |
|---|---|
| expected gene families | [ ] |
| recovered | [ ] |
| precision | [ ] |
| recall | [ ] |
| F1 | [ ] |

**Missed:** [list them, and say why you think each was missed]

**Spurious:** [list them, and say whether you think they are false positives or real
calls absent from the truth set because the reference assemblies are incomplete]

## Host attribution

Of the correctly recovered genes:

| verdict | count |
|---|---|
| correct genus | [ ] |
| incorrect genus | [ ] |
| unassigned | [ ] |
| accuracy | [ ] |

This is the number worth quoting, because it is the one short-read resistome profiling
cannot produce.

## Mobility calls

| call | count |
|---|---|
| plasmid | [ ] |
| chromosome | [ ] |
| ambiguous | [ ] |

The Zymo community includes plasmid-borne content in *Staphylococcus aureus* and
*Escherichia coli*, so a run that calls zero plasmids has probably gone wrong somewhere.
A high `ambiguous` count is not a failure; it is the heuristic declining to guess.

## Threshold sensitivity

Rerun with different cutoffs and record what moves:

```bash
nextflow run . -profile docker,laptop --min_arg_id 80 --outdir results_id80 -resume
nextflow run . -profile docker,laptop --plasmid_score 0.5 --outdir results_ps50 -resume
```

| setting | recall | precision | plasmid calls |
|---|---|---|---|
| default (id 90, cov 60, ps 0.7) | [ ] | [ ] | [ ] |
| id 80 | [ ] | [ ] | [ ] |
| plasmid score 0.5 | [ ] | [ ] | [ ] |

Reporting one configuration and not showing how sensitive it is to the thresholds is the
most common way a pipeline result turns out to be an artefact.

## Reproducibility

- Container digests: `results/pipeline_info/software_versions.yml`
- Full trace with per-process runtime and peak memory: `results/pipeline_info/trace_*.txt`
- Command line and revision hash are captured in `.nextflow.log`

To reproduce exactly:

```bash
nextflow run https://github.com/IshanMaheshwari01/amr-nano-context \
    -r <the commit hash you ran> -profile docker \
    --input assets/samplesheet_zymo.csv --outdir results \
    --kraken2_db <path> --genomad_db <path>
```
