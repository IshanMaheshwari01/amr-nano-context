process NANOPLOT {
    tag "${meta.id}"
    label 'process_low'
    container params.container_nanoplot

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}_nanoplot"), emit: report
    path "versions.yml",                          emit: versions

    script:
    """
    NanoPlot \\
        --fastq ${reads} \\
        --threads ${task.cpus} \\
        --prefix ${meta.id}_ \\
        --outdir ${meta.id}_nanoplot \\
        --tsv_stats \\
        --N50

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        nanoplot: \$(NanoPlot --version | sed 's/NanoPlot //')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p ${meta.id}_nanoplot
    touch versions.yml
    """
}
