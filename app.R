# Interactive version of the mock-community validation.
# Run from the repo root: Rscript -e 'shiny::runApp()'
# Needs shiny and ggplot2: install.packages(c("shiny", "ggplot2"))

library(shiny)
library(ggplot2)

# The expected resistome the pipeline was scored against (truth/ directory).
truth <- read.delim("truth/zymo_expected_resistome.tsv")

# Validation summary numbers. These come from docs/VALIDATION.md, which is the
# full write-up of the ZymoBIOMICS Even mock-community run (ERR3152364,
# subsampled to 1.34 Gbp). 0 false positives across all 65 raw calls.
recovery <- data.frame(
    set = rep(c("AMR only", "all elements"), each = 3),
    metric = factor(rep(c("precision", "recall", "F1"), 2),
                    levels = c("precision", "recall", "F1")),
    score = c(1.000, 0.607, 0.755, 1.000, 0.553, 0.712)
)

host_calls <- data.frame(
    set = c("AMR only", "all elements"),
    correct = c(17, 53),
    total = c(17, 53)
)

completeness <- data.frame(
    organism = c("Enterococcus", "Limosilactobacillus", "Bacillus", "Staphylococcus",
                 "Pseudomonas", "Listeria", "Escherichia", "Salmonella"),
    contigs = c(1, 2, 3, 4, 3, 2, 6, 2),
    assembled_mb = c(2.83, 1.90, 4.04, 2.73, 6.80, 3.01, 4.92, 4.81),
    expected_mb = c(2.85, 1.91, 4.05, 2.73, 6.79, 2.99, 4.88, 4.76),
    completeness = c(0.993, 0.995, 0.998, 1.000, 1.001, 1.007, 1.008, 1.011)
)

ui <- fluidPage(
    titlePanel("amr-nano-context validation"),
    p("Long-read resistome profiling, scored on a mock community where every",
      "resistance gene and its host are known in advance."),
    h4("Gene recovery"),
    plotOutput("recovery", height = "320px"),
    p("AMR elements only: 28 expected, 17 recovered, 0 false positives.",
      "All elements (including stress and virulence): 94 expected, 52 recovered,",
      "0 false positives. The pipeline under-reports, it does not invent."),
    h4("Host attribution"),
    p("Every call was assigned the correct genus (scored at genus level, see",
      "docs/VALIDATION.md for why)."),
    plotOutput("host", height = "260px"),
    h4("Expected resistome by element type"),
    plotOutput("element_types", height = "300px"),
    h4("Assembly completeness by member"),
    tableOutput("completeness")
)

server <- function(input, output) {
    output$recovery <- renderPlot({
        ggplot(recovery, aes(x = metric, y = score, fill = set)) +
            geom_col(position = position_dodge(0.7), width = 0.6) +
            ylim(0, 1) +
            labs(x = NULL, y = "score", fill = NULL) +
            theme_minimal(base_size = 13) +
            theme(legend.position = "top")
    })

    output$host <- renderPlot({
        ggplot(host_calls, aes(x = set, y = correct)) +
            geom_col(fill = "#4C72B0", width = 0.5) +
            geom_text(aes(label = paste0(correct, " / ", total)), vjust = -0.5) +
            ylim(0, 65) +
            labs(x = NULL, y = "calls with correct genus") +
            theme_minimal(base_size = 13)
    })

    output$element_types <- renderPlot({
        ggplot(truth, aes(x = element_type)) +
            geom_bar(fill = "#4C72B0") +
            labs(x = NULL, y = "expected elements") +
            theme_minimal(base_size = 13)
    })

    output$completeness <- renderTable({
        d <- completeness
        d$completeness <- sprintf("%.3f", d$completeness)
        names(d) <- c("organism", "contigs", "assembled Mb", "expected Mb", "completeness")
        d
    }, rownames = FALSE, digits = 2)
}

shinyApp(ui, server)
