.onAttach <- function(libname, pkgname) {
  packageStartupMessage(paste(
    "plnr",
    utils::packageDescription("plnr")$Version,
    "https://folkehelseinstituttet.github.io/plnr"
  ))
}
