# Runbook

Start to finish on Ubuntu. Times assume 6 cores, 16 GB RAM and domestic broadband.

## Before you start

Check what you have:

```bash
nproc                       # cores
free -g                     # RAM; you want 16 or more
df -h ~                     # free disk; you want 60 GB or more
```

If you have less than 16 GB, cut `TARGET_BASES` in step 3 to `500000000` and expect a
more fragmented assembly. The pipeline still works, the validation numbers are just
worse, and you should say so in the README rather than hide it.

## 1. Setup, 20 minutes

```bash
git clone https://github.com/IshanMaheshwari01/amr-nano-context
cd amr-nano-context
bash scripts/00_setup_ubuntu.sh
```

If Docker was newly installed you need a new shell before it works without sudo:

```bash
newgrp docker
docker run --rm hello-world
```

Then confirm Nextflow can parse the workflow before anything expensive starts:

```bash
python3 test-data/make_test_data.py
mkdir -p test-data/db_stub
nextflow run . -profile test -stub-run --outdir results_test
```

This should finish in under a minute and print a green summary. If it fails, the problem
is syntax or channel wiring and you have saved yourself several hours.

Run the unit tests too:

```bash
pip3 install --user pandas pytest
python3 -m pytest tests/ -v
```

## 2. Databases, 30 to 60 minutes

Open https://benlangmead.github.io/aws-indexes/k2 and copy the **Standard-8** download
link. The filename carries a build date so it changes.

```bash
K2_URL='<paste the Standard-8 link here>' bash scripts/02_get_databases.sh
```

That fetches Kraken2 (about 8 GB) and geNomad (about 1.5 GB). The geNomad download runs
inside its own container, so Docker must be working first.

## 3. Data, 30 to 60 minutes

```bash
bash scripts/01_get_data.sh ERR3152364 1500000000
```

ERR3152364 is the GridION run of the ZymoBIOMICS Even community: 3.49M reads, 14.4 Gbp,
about 14 GB compressed. The script resolves the FASTQ URL through the ENA API rather than
hardcoding it, then streams the file through `scripts/take_bases.py`, which decompresses
on the fly and stops once the base target is met. curl gets SIGPIPE and quits, so only
about a tenth of the file crosses the network.

ENA's HTTPS endpoint drops connections fairly often on long transfers. The script retries
up to five times; raise it with `MAX_ATTEMPTS=10` if your connection is bad.

Streaming is not resumable. If it keeps failing, take the whole file instead, which is:

```bash
FULL_DOWNLOAD=1 bash scripts/01_get_data.sh ERR3152364 1500000000
```

That needs 14 GB of disk and an hour or more, but `curl -C -` picks up where it left off,
so repeated dropouts cost nothing. Use it if you want the full dataset for later anyway.

To redo a subsample you already have, set `FORCE=1`.

It also fetches the Illumina isolate assemblies used to build the truth set.

## 4. Truth set, 15 minutes

Look at the FASTA headers before splitting, because the format has changed between
releases:

```bash
grep '>' refs/Zymo-Isolates-SPAdes-Illumina.fasta | head
```

Then split and adjust `--pattern` if the default regex does not fit:

```bash
python3 scripts/split_refs.py \
    --fasta refs/Zymo-Isolates-SPAdes-Illumina.fasta \
    --outdir refs/per_organism
ls refs/per_organism
```

You want roughly ten files, one per organism. Then build the expected resistome. This
needs `amrfinder`, easiest via the container:

```bash
mkdir -p truth
docker run --rm -v "$PWD":/work -w /work \
    quay.io/biocontainers/ncbi-amrfinderplus:4.0.19--hf69ffd2_0 \
    bash -c "amrfinder -u || true"   # updates the bundled DB once, optional

python3 bin/build_truth_set.py \
    --genome-dir refs/per_organism \
    --out truth/zymo_expected_resistome.tsv \
    --amrfinder-cmd amrfinder
```

If `amrfinder` is not on your host PATH, run the whole script inside the container:

```bash
docker run --rm -v "$PWD":/work -w /work \
    quay.io/biocontainers/ncbi-amrfinderplus:4.0.19--hf69ffd2_0 \
    python3 bin/build_truth_set.py --genome-dir refs/per_organism \
        --out truth/zymo_expected_resistome.tsv
```

Sanity check: `wc -l truth/zymo_expected_resistome.tsv`. The Zymo community is not
heavily resistant, so expect on the order of ten to forty entries, dominated by
intrinsic genes in *Enterococcus faecalis* and *Staphylococcus aureus*. A file with two
rows means the split did not work.

## 5. The run, 4 to 8 hours

```bash
nextflow run . -profile docker,laptop \
    --input assets/samplesheet_zymo.csv \
    --outdir results \
    --kraken2_db databases/k2_standard_08gb \
    --genomad_db databases/genomad_db \
    -resume
```

metaFlye is the long pole, usually 3 to 6 hours at 1.5 Gbp on 6 cores. Kraken2 will look
frozen for a minute or two while it loads the database into RAM; that is normal.

Leave `-resume` on. If something dies at hour five you restart from that step, not from
the beginning.

Watch it from another terminal:

```bash
tail -f .nextflow.log
```

## 6. Read the results

```
results/
├── assembly/           metaFlye contigs and assembly_info.txt
├── kraken2_reads/      community composition
├── resistome/          *_arg_context.tsv        <- the point of the pipeline
├── validation/         *_validation.tsv and .json
├── multiqc/            multiqc_report.html
└── pipeline_info/      timeline, trace, DAG, software versions
```

Start here:

```bash
column -t -s$'\t' results/resistome/zymo_even_gridion_arg_context.tsv | less -S
cat results/validation/zymo_even_gridion_validation.json
```

## 7. Write down what happened

Fill in `docs/VALIDATION.md` with your actual numbers, including the misses. A validation
document that reports recall of 1.00 and no caveats reads as untested. One that says
"recovered 11 of 14 expected gene families; the three misses were all in the two yeast
members, which metaFlye did not assemble well at this depth" reads as someone who looked.

## When it fails

**`docker: permission denied`** - you have not re-logged since the install. `newgrp docker`.

**Container pull 404** - a biocontainer tag has moved. Find the current tag at
`https://quay.io/repository/biocontainers/<tool>?tab=tags` and edit
`conf/containers.config`. That is the only file that needs changing.

**Killed at Flye, exit 137** - out of memory. Drop `--max_memory` in the run command, or
subsample to fewer bases and rerun step 3.

**Kraken2 exits immediately with a database error** - the extracted directory must
contain `hash.k2d`, `opts.k2d` and `taxo.k2d` at its top level. If they are one directory
deeper, point `--kraken2_db` at that inner directory.

**geNomad output not found** - geNomad nests output under a directory named after the
input file, and that name changes with the assembly filename. The module handles this
with `find`, but if it breaks, look at what is actually under `work/*/genomad_out`.

**Everything is slow and the fan is loud** - that is metaFlye. Go and do something else
for four hours.

## Committing as you go

Do not push this as one commit at the end. The commit history is part of what is being
read.

```bash
git checkout -b dev
# ... work ...
git add modules/local/genomad.nf
git commit -m "Add geNomad module for plasmid/chromosome classification"
```

Reasonable commit sequence:

1. `Scaffold pipeline: config, profiles, CI stub run`
2. `Add read QC subworkflow (nanoq, NanoPlot, SeqKit)`
3. `Add Kraken2 and Bracken taxonomic profiling`
4. `Add metaFlye metagenome assembly`
5. `Add AMRFinderPlus and ABRicate ARG calling`
6. `Add geNomad plasmid classification`
7. `Add ARG context join with unit tests`
8. `Add resistome validation against mock community truth set`
9. `Document validation results and known limitations`

Then open a PR from `dev` to `main` and let CI run on it. A repo with a passing CI badge
and a real PR history looks different from a repo with one commit called "initial commit".
