# Contributing to mortalityAdherence

Thank you for your interest in contributing!

## How to contribute

### Reporting bugs

Please open an issue at <https://github.com/yourusername/mortalityAdherence/issues>
and include:

- A minimal reproducible example (`reprex::reprex()` output is ideal)
- The output of `sessionInfo()`
- The exact error message or unexpected behaviour

### Suggesting features

Open an issue labelled **enhancement** describing the use case and the
proposed API change.

### Submitting a pull request

1. Fork the repository and create a new branch from `main`.
2. Install development dependencies:
   ```r
   install.packages(c("devtools", "roxygen2", "testthat", "covr"))
   ```
3. Make your changes and document them with roxygen2 comments.
4. Regenerate documentation:
   ```r
   devtools::document()
   ```
5. Run the full test suite:
   ```r
   devtools::test()
   ```
6. Run `R CMD CHECK` with no errors or warnings:
   ```r
   devtools::check()
   ```
7. Push your branch and open a pull request against `main`.

## Code style

- Follow the [tidyverse style guide](https://style.tidyverse.org/) for
  variable names and spacing.
- All exported functions must have complete roxygen2 documentation including
  `@param`, `@return`, `@examples`, and `@seealso` sections.
- Every new test function must have corresponding tests in `tests/testthat/`.

## Adding a new mortality table

1. Add the raw data to `data-raw/`.
2. Register the table in `R/tables.R` (the `.BUILT_IN_TABLES` data frame).
3. Add the column to `R/data_mortality_tables.R`.
4. Update `R/data_docs.R` to document the new column.
5. Re-run `data-raw/build_mortality_tables.R` and rebuild the package.

## License

By contributing you agree that your contributions will be licensed under
the MIT License.
