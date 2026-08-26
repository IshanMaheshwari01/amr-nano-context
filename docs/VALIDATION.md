# Validation

Run date: 26 August 2026. All figures come from a single completed run and can be regenerated
from the commit recorded in `results/pipeline_info/`.

## What is being validated

The ZymoBIOMICS Microbial Community Standard (D6300) contains eight bacteria and two yeasts at
defined abundances. Because the membership is known, the resistome is knowable: running
AMRFinderPlus over each member's reference genome gives the set of elements a perfect analysis
of this sample would return.

Data: ERR3152364, Oxford Nanopore GridION, R9.4.1, 3.49M reads, 14.38 Gbp total, released
CC BY 4.0 by the Loman lab (Nicholls et al., GigaScience 2019). Subsampled to the first
328,698 reads (1.34 Gbp) to stay tractable on a 16 GB machine.

The two yeasts were excluded from the truth set. AMRFinderPlus is a bacterial tool, and at 2%
abundance neither assembles at this depth.

### What this does and does not prove

It proves the pipeline recovers, from raw reads, what AMRFinderPlus finds in the finished
genomes of the same organisms. It does not prove those calls are biologically correct: the
truth set inherits AMRFinderPlus's database and its blind spots. This tests the pipeline, not
the underlying reference data.

Host attribution is scored at genus level rather than species. Kraken2 on a
metagenome-assembled contig is more reliable at genus, and claiming species-level accuracy
would overstate what the method supports. One call illustrates why: `qacG` on contig_41 was
labelled *Staphylococcus agnetis*, which is not a community member. The genus is right, the
species is a near neighbour, and species-level scoring would have counted a correct
attribution as wrong.

### Versions

| component | version |
|---|---|
| Kraken2 database | PlusPF-8, 2026-06-26 |
| geNomad database | v1.7 |
| AMRFinderPlus | 4.0.19, database 2025-07-16.1 |
| Nextflow | 26.04.6 |

PlusPF-8 rather than Standard-8 because the community contains two yeasts and Standard has no
fungal genomes, which would make a real absence indistinguishable from a database gap.

The AMRFinderPlus database is pinned rather than updated at runtime. A newer database
(2026-08-07.1) exists but needs software 4.2. Pinning matters more than currency here: the
truth set and the pipeline must use the same database or the comparison is confounded.

## Assembly

| metric | value |
|---|---|
| reads after filtering | 328,698 |
| total bases | 1.34 Gbp |
| contigs | 206 |
| total assembly length | 32,605,831 bp |
| circular contigs | 12 |

Per-member completeness, from summing contig length by Kraken2 genus assignment:

| organism | contigs | assembled Mb | expected Mb | completeness | median cov |
|---|---|---|---|---|---|
| Enterococcus | 1 | 2.83 | 2.85 | 0.993 | 40.0 |
| Limosilactobacillus | 2 | 1.90 | 1.91 | 0.995 | 214.0 |
| Bacillus | 3 | 4.04 | 4.05 | 0.998 | 42.0 |
| Staphylococcus | 4 | 2.73 | 2.73 | 1.000 | 36.5 |
| Pseudomonas | 3 | 6.80 | 6.79 | 1.001 | 11.0 |
| Listeria | 2 | 3.01 | 2.99 | 1.007 | 68.5 |
| Escherichia | 6 | 4.92 | 4.88 | 1.008 | 16.0 |
| Salmonella | 2 | 4.81 | 4.76 | 1.011 | 20.5 |

Every member assembled essentially completely, several into single contigs. This matters for
reading the recall figures below: the elements that were missed were missed from complete
genomes, not absent ones.

## Truth set

102 element/host pairs across 8 reference genomes:

| element type | count |
|---|---|
| VIRULENCE | 42 |
| STRESS | 32 |
| AMR | 28 |

AMRFinderPlus `--plus` reports stress (metal and biocide tolerance) and virulence elements
alongside resistance genes. Only the AMR subset is resistome, so metrics are reported for that
subset as the headline and for all elements as a secondary figure. Scoring virulence genes
inside a number called "resistome recall" would measure the wrong thing.

## Gene recovery

**AMR elements only:**

| metric | value |
|---|---|
| expected | 28 |
| recovered | 17 |
| false positives | 0 |
| precision | 1.000 |
| recall | 0.607 |
| F1 | 0.755 |

**All element types:**

| metric | value |
|---|---|
| expected | 94 |
| recovered | 52 |
| false positives | 0 |
| precision | 1.000 |
| recall | 0.553 |
| F1 | 0.712 |

Recall by element type: STRESS 0.750, AMR 0.607, VIRULENCE 0.405.

**Zero false positives across 65 raw calls.** Everything reported was present in the reference
genomes. The pipeline under-reports; it does not invent.

## Host attribution

| verdict | AMR only | all elements |
|---|---|---|
| correct genus | 17 | 53 |
| incorrect genus | 0 | 0 |
| unassigned | 0 | 0 |
| accuracy | 1.000 | 1.000 |

This is the figure worth quoting, because short-read resistome profiling cannot produce it at
all. Every recovered element was attributed to the correct source organism.

The caveat is that this is a mock community of eight well-separated, fully sequenced organisms,
which is close to the easiest possible case. An environmental sample with related strains,
uneven abundance and uncultured members would be considerably harder, and this number should
not be read as expected performance there.

## Mobility calls

| call | count |
|---|---|
| chromosome | 46 |
| ambiguous | 6 |
| plasmid | 1 |

One plasmid-borne resistance gene was resolved: `aadD1`, aminoglycoside resistance, on
contig_206, a small circular contig assigned to *Staphylococcus aureus*. That single row is
what the pipeline exists to produce. A short-read resistome would report `aadD1` present and
stop there.

Six ambiguous calls are not failures. The heuristic returns `ambiguous` when neither the
geNomad score nor contig circularity gives a confident signal, rather than defaulting to
chromosome. A pipeline that always commits produces a cleaner table and a worse one.

One plasmid call is low for this community. Whether that reflects genuine plasmid content at
this depth or a limitation in recovering plasmids from a metagenome assembly is not resolved
here.

## Why elements were missed: an open question

Of 42 missed elements, 8 were called by AMRFinderPlus and removed by the pipeline's identity
and coverage thresholds, and 34 were absent from the caller's output entirely.

The 8 filtered:

| element | type | method | coverage | identity |
|---|---|---|---|---|
| aaiC | VIRULENCE | PARTIALX | 51.19 | 100.00 |
| fdeC | VIRULENCE | PARTIALX | 51.98 | 93.21 |
| invA | VIRULENCE | PARTIALX | 52.85 | 97.79 |
| tet(L) | AMR | INTERNAL_STOP | 53.49 | 93.88 |
| asr | STRESS | PARTIALX | 54.90 | 100.00 |
| blaI | AMR | INTERNAL_STOP | 57.14 | 100.00 |
| lntA | VIRULENCE | PARTIALX | 88.63 | 85.56 |
| iroC | VIRULENCE | INTERNAL_STOP | 91.39 | 78.11 |

`INTERNAL_STOP`, and partial hits at high identity but low coverage, are the signature of
consensus error: a frameshift truncates the predicted protein, so a gene that is present
scores as a fragment.

Recall varies sharply by source organism, and this part is not explained:

| organism | AMR expected | recovered | recall |
|---|---|---|---|
| Enterococcus faecalis | 1 | 1 | 1.000 |
| Pseudomonas aeruginosa | 9 | 8 | 0.889 |
| Escherichia coli | 4 | 3 | 0.750 |
| Staphylococcus aureus | 8 | 4 | 0.500 |
| Listeria monocytogenes | 2 | 1 | 0.500 |
| Salmonella enterica | 2 | 0 | 0.000 |
| Bacillus subtilis | 2 | 0 | 0.000 |

This does not track assembly completeness, which is uniform at 0.99 to 1.01 across all eight
members. It does not track coverage either: *Pseudomonas* has the lowest median coverage in the
assembly at 11x and the highest recall, while *Bacillus* at 42x recovered nothing.

Three explanations were considered and none survives the data. Assembly fragmentation is ruled
out by the completeness table. Low coverage is ruled out by the inverse relationship above.
Plasmid loss would not explain *Bacillus subtilis*, whose missing elements are chromosomal.

The remaining hypothesis is consensus error in the unpolished assembly, supported by the
`INTERNAL_STOP` calls but not demonstrated. R9.4.1 chemistry from 2019 has substantially higher
raw error than current chemistry, and the metaFlye output here is unpolished.

**The experiment that would settle it** is to add Medaka polishing and rerun. If recall rises
and the `INTERNAL_STOP` calls resolve, consensus error is the cause and the cost of skipping
polishing is quantified. If recall does not move, the cause is elsewhere. That is the next
piece of work on this pipeline and it has not been done.

## Threshold sensitivity

Not yet run, and this is a gap. The 8 filtered elements sit between 51% and 91% coverage, so
lowering `--min_arg_cov` from 60 would recover some at an unmeasured cost to precision.
Reporting one threshold configuration without showing its sensitivity is the most common way a
pipeline result turns out to be an artefact.

```bash
nextflow run . -profile docker,laptop --min_arg_cov 45 --outdir results_cov45 -resume
```

## Reproducibility

- Container digests and tool versions: `results/pipeline_info/software_versions.yml`
- Per-process runtime and peak memory: `results/pipeline_info/trace.txt`
- Command line and revision hash: `.nextflow.log`

```bash
nextflow run https://github.com/IshanMaheshwari01/amr-nano-context \
    -r <commit hash> -profile docker \
    --input assets/samplesheet_zymo.csv --outdir results \
    --kraken2_db <path> --genomad_db <path> --amrfinder_db <path>
```
