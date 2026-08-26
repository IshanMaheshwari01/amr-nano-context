/*
 * Classifies each contig as chromosome, plasmid or virus. This is the step that
 * turns "gene X is present" into "gene X is present on a mobile element".
 */
process GENOMAD {
    tag "${meta.id}"
    label 'process_high'
    container params.container_genomad

    input:
    tuple val(meta), path(assembly)
    path db

    output:
    tuple val(meta), path("${meta.id}_genomad_summary.tsv"), emit: summary
    tuple val(meta), path("genomad_out"),                    emit: dir
    path "versions.yml",                                     emit: versions

    script:
    // mmseqs2 loads its target database into memory. On the default --splits 0
    // (decide automatically) it assumes it can have the whole machine, and on a
    // laptop the OOM killer takes it. Splitting the search trades runtime for
    // peak memory. Escalating with task.attempt means a retry splits further
    // rather than failing the same way twice.
    def splits = (params.genomad_splits as int) * task.attempt
    """
    genomad end-to-end \\
        --cleanup \\
        --splits ${splits} \\
        --threads ${task.cpus} \\
        ${assembly} \\
        genomad_out \\
        ${db}

    # geNomad nests its outputs under a directory named after the input file.
    SUMMARY=\$(find genomad_out -name '*_aggregated_classification.tsv' | head -n1)
    if [ -z "\$SUMMARY" ]; then
        printf 'seq_name\\tchromosome_score\\tplasmid_score\\tvirus_score\\n' > ${meta.id}_genomad_summary.tsv
    else
        cp "\$SUMMARY" ${meta.id}_genomad_summary.tsv
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        genomad: \$(genomad --version | sed 's/genomad, version //')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p genomad_out
    printf 'seq_name\\tchromosome_score\\tplasmid_score\\tvirus_score\\n' > ${meta.id}_genomad_summary.tsv
    printf 'contig_1\\t0.9\\t0.05\\t0.05\\n' >> ${meta.id}_genomad_summary.tsv
    touch versions.yml
    """
}
