process BRACKEN {
    tag "${meta.id}"
    label 'process_low'
    container params.container_bracken

    input:
    tuple val(meta), path(report)
    path db

    output:
    tuple val(meta), path("${meta.id}.bracken.tsv"), emit: abundance
    path "versions.yml",                             emit: versions

    script:
    """
    # Bracken needs a read-length-matched distribution file in the database.
    # Long-read data has no single read length; 150 is the distribution that
    # ships with the prebuilt databases and is what is being approximated here.
    # This is a documented limitation, not a silent assumption - see docs/VALIDATION.md
    bracken \\
        -d ${db} \\
        -i ${report} \\
        -o ${meta.id}.bracken.tsv \\
        -r 150 \\
        -l S \\
        -t 10

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bracken: \$(bracken -v 2>&1 | sed 's/Bracken v//')
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}.bracken.tsv
    touch versions.yml
    """
}
