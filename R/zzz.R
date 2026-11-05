# Startup message shown by library(mortalityAdherence).
# The Python version prints the same text on import.
# Silence it with suppressPackageStartupMessages(library(mortalityAdherence)).

.startup_message <- function() {
  paste0(
    "mortalityAdherence ", utils::packageVersion("mortalityAdherence"), "\n",
    "Os novos testes de ader\u00eancia desenvolvidos s\u00e3o mais adequados ",
    "quando aplicados a idades superiores a 30 anos.\n",
    "The new adherence tests are best suited to ages above 30.\n",
    "Reference: de Melo, Graziadei & Targino (2026), SSRN 6668699."
  )
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(.startup_message())
}
