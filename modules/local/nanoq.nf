process NANOQ {
    tag "${meta.id}"
    label 'process_low'
    container params.container_nanoq

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}_filt.fastq.gz"), emit: reads
    tuple val(meta), path("${meta.id}_nanoq.json"),    emit: report
    path "versions.yml",                               emit: versions

    script:
    def args = task.ext.args ?: ''
    """
    nanoq \\
        --input ${reads} \\
        ${args} \\
        --output-type g \\
        --output ${meta.id}_filt.fastq.gz \\
        --json \\
        --stats \\
        --report ${meta.id}_nanoq.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        nanoq: \$(nanoq --version | sed 's/nanoq //')
    END_VERSIONS
    """

    stub:
    """
    echo "" | gzip > ${meta.id}_filt.fastq.gz
    echo '{}' > ${meta.id}_nanoq.json
    touch versions.yml
    """
}
