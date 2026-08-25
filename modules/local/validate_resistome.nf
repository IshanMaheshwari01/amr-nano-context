/*
 * Compares the recovered resistome against a truth set derived from the
 * reference genomes of the organisms known to be in the sample. Without this
 * the pipeline produces plausible output and no evidence that it is correct.
 */
process VALIDATE_RESISTOME {
    tag "${meta.id}"
    label 'process_low'
    container params.container_pandas

    input:
    tuple val(meta), path(observed), path(truth)

    output:
    tuple val(meta), path("${meta.id}_validation.tsv"),   emit: report
    tuple val(meta), path("${meta.id}_validation.json"),  emit: metrics
    path "versions.yml",                                  emit: versions

    script:
    """
    validate_resistome.py \\
        --sample ${meta.id} \\
        --observed ${observed} \\
        --truth ${truth} \\
        --out ${meta.id}_validation.tsv \\
        --out-json ${meta.id}_validation.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_validation.tsv
    echo '{}' > ${meta.id}_validation.json
    touch versions.yml
    """
}
