/*
 * A second ARG caller against different databases. Running two is deliberate:
 * where AMRFinderPlus and CARD disagree is itself a result, and a resistome
 * reported from one database alone hides that disagreement.
 */
process ABRICATE {
    tag "${meta.id}"
    label 'process_medium'
    container params.container_abricate

    input:
    tuple val(meta), path(assembly)

    output:
    tuple val(meta), path("${meta.id}_abricate_card.tsv"), emit: report
    tuple val(meta), path("${meta.id}_abricate_resfinder.tsv"), emit: resfinder
    path "versions.yml",                                    emit: versions

    script:
    def args = task.ext.args ?: ''
    """
    abricate --db card      ${args} --threads ${task.cpus} ${assembly} > ${meta.id}_abricate_card.tsv
    abricate --db resfinder ${args} --threads ${task.cpus} ${assembly} > ${meta.id}_abricate_resfinder.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        abricate: \$(abricate --version | sed 's/abricate //')
        abricate_db: \$(abricate --list | grep -E '^(card|resfinder)' | tr '\\n' ';')
    END_VERSIONS
    """

    stub:
    """
    printf '#FILE\\tSEQUENCE\\tSTART\\tEND\\tSTRAND\\tGENE\\tCOVERAGE\\tCOVERAGE_MAP\\tGAPS\\t%%COVERAGE\\t%%IDENTITY\\tDATABASE\\tACCESSION\\tPRODUCT\\tRESISTANCE\\n' > ${meta.id}_abricate_card.tsv
    printf '#FILE\\tSEQUENCE\\tSTART\\tEND\\tSTRAND\\tGENE\\tCOVERAGE\\tCOVERAGE_MAP\\tGAPS\\t%%COVERAGE\\t%%IDENTITY\\tDATABASE\\tACCESSION\\tPRODUCT\\tRESISTANCE\\n' > ${meta.id}_abricate_resfinder.tsv
    touch versions.yml
    """
}
