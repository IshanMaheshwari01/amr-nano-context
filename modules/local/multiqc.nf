process MULTIQC {
    label 'process_low'
    container params.container_multiqc

    input:
    path multiqc_files, stageAs: "?/*"
    path config

    output:
    path "multiqc_report.html", emit: report
    path "multiqc_data",        emit: data

    script:
    """
    multiqc --force --config ${config} .
    """

    stub:
    """
    touch multiqc_report.html
    mkdir -p multiqc_data
    """
}
