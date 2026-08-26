# amr-nano-context

Long-read metagenomic resistome profiling that reports where each resistance gene is,
not just that it is there.

[![CI](https://github.com/IshanMaheshwari01/amr-nano-context/actions/workflows/ci.yml/badge.svg)](https://github.com/IshanMaheshwari01/amr-nano-context/actions/workflows/ci.yml)

## The problem

Standard resistome profiling gives you a list: `blaTEM`, `tet(M)`, `sul1`, and so on.
That list answers "is resistance present" and nothing else. Two things it cannot tell you
are usually the two things you want to know:

1. **Is the gene mobile?** A resistance gene on a plasmid can move between species.
   The same gene on a chromosome largely cannot. Epidemiologically these are different
   findings, and short reads cannot distinguish them because the read is shorter than the
   distance between the gene and any marker that would identify its replicon.
2. **Which organism is carrying it?** A resistance gene in a harmless environmental
   bacterium is a different risk from the same gene in a pathogen.

Long reads keep that linkage intact. This pipeline uses them to report gene, replicon
type and host organism as one call.

## What it does

```
reads ──▶ nanoq (filter) ──▶ NanoPlot / SeqKit (QC)
            │
            ├──▶ Kraken2 + Bracken ──────────────▶ community composition
            │
            └──▶ metaFlye (assembly)
                     │
                     ├──▶ AMRFinderPlus ──┐
                     ├──▶ ABRicate (CARD, ResFinder) ─┤
                     ├──▶ geNomad (plasmid / chromosome) ─┼──▶ arg_context.py ──▶ resistome table
                     ├──▶ Kraken2 on contigs (host) ──────┘             │
                     └──▶ Flye assembly_info (length, circularity) ─────┘
                                                                        │
                                              truth set ────────────────┴──▶ validation metrics
```

Output is one TSV with a row per resistance gene:

| gene | drug_class | contig | contig_len | circular | mobility | mobility_evidence | host_taxon | card_agrees |
|---|---|---|---|---|---|---|---|---|
| tet(M) | TETRACYCLINE | contig_14 | 2,904,551 | N | chromosome | contig length exceeds plasmid threshold | Enterococcus faecalis | True |
| blaTEM-1B | BETA-LACTAM | contig_88 | 5,412 | Y | plasmid | circular contig of 5412 bp | Escherichia coli | True |

The `mobility_evidence` column exists so the call can be argued with rather than taken
on trust.

## Validation

The pipeline is run against the ZymoBIOMICS Even mock community sequenced on Oxford
Nanopore GridION by the Loman lab (ERR3152364, CC BY 4.0). Because the ten member
organisms are known, the expected resistome is knowable: `bin/build_truth_set.py` runs
AMRFinderPlus over each member's reference genome and the union of those calls is what
the pipeline should recover.

Two metrics are reported:

- **Gene recovery** - precision, recall and F1 over gene families found in the assembly
  versus found in the reference genomes.
- **Host attribution accuracy** - of the genes correctly recovered, what fraction were
  assigned to the right genus. This is the metric a short-read resistome profile cannot
  produce at all.

Results and their caveats are in [docs/VALIDATION.md](docs/VALIDATION.md).

## Quick start

```bash
git clone https://github.com/IshanMaheshwari01/amr-nano-context
cd amr-nano-context

# one-time setup: docker, nextflow, java
bash scripts/00_setup_ubuntu.sh

# check the wiring without running anything real
nextflow run . -profile test -stub-run --outdir results_test

# databases (about 10 GB total, one-off)
K2_URL='<PlusPF-8 link from https://benlangmead.github.io/aws-indexes/k2>' \
  bash scripts/02_get_databases.sh
bash scripts/03_get_amrfinder_db.sh

# data
bash scripts/01_get_data.sh ERR3152364 1500000000

# truth set
python3 scripts/split_zymo_refs.py --fasta refs/Zymo-Isolates-SPAdes-Illumina.fasta \
    --outdir refs/per_organism
python3 bin/build_truth_set.py --genome-dir refs/per_organism \
    --out truth/zymo_expected_resistome.tsv \
    --amrfinder-cmd ./scripts/amrfinder-docker

# the real run
nextflow run . -profile docker,laptop \
    --input assets/samplesheet_zymo.csv \
    --outdir results \
    --kraken2_db databases/k2_pluspf_08gb \
    --genomad_db databases/genomad_db \
    --amrfinder_db databases/amrfinderplus
```

Full step by step, including timings and what to do when a step fails, is in
[docs/RUNBOOK.md](docs/RUNBOOK.md).

## Requirements

Nextflow 24.04 or later, Docker, Java 17, and roughly 60 GB of free disk. The stub run is
verified on Nextflow 24.10.5 and 26.04.6; the config avoids variable and method declarations
in config files, which Nextflow 26's parser rejects. Kraken2
Standard-8 holds about 8 GB resident while it runs, so 16 GB of RAM is the practical
floor. The `laptop` profile caps resources at 6 CPUs and 12 GB.

## Design notes

**Container tags are pinned in one file.** `conf/containers.config` holds every image
tag. Nothing else references a container. When a tag rots there is exactly one file to
edit.

**Thresholds live in config, not in code.** Identity, coverage and the plasmid-score
cutoff are `params`, set in `conf/modules.config`. Changing an ARG calling threshold
does not mean touching the process that runs the tool.

**Two ARG databases on purpose.** AMRFinderPlus drives the results table; CARD via
ABRicate runs alongside it and its agreement is recorded per contig. Where they disagree
is worth knowing, and a resistome reported from a single database hides that.

**"Ambiguous" is an allowed answer.** The mobility heuristic returns `ambiguous` rather
than defaulting to chromosome when neither geNomad nor circularity gives a confident
signal. A pipeline that always commits produces a cleaner table and a worse one.

**The stub run is the CI test.** Every process has a `stub:` block, so CI can execute
the whole DAG in seconds without databases or containers. It proves the channel wiring,
not the biology. The biology is proved by the mock community run.

**Resource requests clamp to the host.** Nextflow's local executor errors outright when a
task asks for more CPU or RAM than the machine has, so a config written on a 16 GB desktop
would fail on a 4 GB CI runner. `check_max` clamps to the host when running locally and
leaves the request alone when `cap_resources_to_host = false`, which is what a cluster
profile sets: the login node's specs say nothing about the compute nodes.

## Known limitations

These are real and are not worked around:

- Bracken is run with a 150 bp read-length distribution because that is what ships with
  the prebuilt databases. Long reads have no single read length, so Bracken abundances
  here are approximate. Kraken2 classification itself is unaffected.
- Assemblies are unpolished. Medaka would improve consensus accuracy and therefore ARG
  identity scores, at a large cost in runtime. Adding it is the obvious next change.
- Contig-level Kraken2 assigns a taxon to the whole contig. A chimeric or
  cross-contaminated contig gets one label, and the ARG inherits it.
- geNomad's plasmid score is not a proof of mobility. A contig can score highly and be
  a chromosomal region rich in mobile-element genes.
- The truth set is derived from AMRFinderPlus run on reference genomes, so it inherits
  AMRFinderPlus's database and blind spots. It measures whether the pipeline recovers
  what the same tool sees in a perfect assembly, not ground truth in an absolute sense.

## Relationship to nf-core/mag

[nf-core/mag](https://nf-co.re/mag) is the production-grade choice for general
metagenome assembly and binning, and it is more thoroughly tested than this. This
pipeline is deliberately narrower: it exists to do the ARG-to-context join, which mag
does not do, and to be small enough to read end to end. Module structure and config
layout follow nf-core conventions so that the two are legible to the same person.

## Citations

Tools and data are cited in [CITATIONS.md](CITATIONS.md). The mock community data is
Nicholls, Quick, Tang and Loman, GigaScience 2019, doi:10.1093/gigascience/giz043.

## License

MIT. Data used for validation is CC BY 4.0 from the Loman lab.
