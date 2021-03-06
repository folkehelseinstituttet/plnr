#' plan class description
#'
#' An argset is:
#' - a set of arguments
#'
#' An analysis is:
#' - one argset
#' - one function
#'
#' A plan is:
#' - one data pull
#' - a list of analyses
#'
#' @import data.table
#' @import R6
#' @import foreach
#' @export
#' @exportClass Plan
Plan <- R6::R6Class(
  "Plan",
  portable = FALSE,
  cloneable = TRUE,
  public = list(
    data = list(),
    analyses = list(),
    argset_name = "argset",
    verbose = FALSE,
    use_foreach = FALSE,
    pb_progress = NULL,
    pb_progressor = NULL,
    initialize = function(argset_name = "argset", verbose = interactive() | config$force_verbose, use_foreach = FALSE) {
      argset_name <<- argset_name
      verbose <<- verbose
      # null = program decides
      # false = use loop
      # true = use foreach
      use_foreach <<- use_foreach
    },
    add_data = function(name, fn = NULL, fn_name = NULL, direct = NULL) {
      stopifnot(is.null(fn) | is.function(fn))
      stopifnot(is.null(fn_name) | is.character(fn_name))

      data[[length(data) + 1]] <<- list(
        fn = fn,
        fn_name = fn_name,
        direct = direct,
        name = name
      )
    },
    add_argset = function(name = uuid::UUIDgenerate(), ...) {
      if (is.null(analyses[[name]])) analyses[[name]] <- list()

      dots <- list(...)
      analyses[[name]][[argset_name]] <<- dots
    },
    add_argset_from_df = function(df) {
      df <- as.data.frame(df)
      for (i in 1:nrow(df)) {
        argset <- df[i, ]
        do.call(add_argset, argset)
      }
    },
    add_argset_from_list = function(l) {
      for (i in seq_along(l)) {
        argset <- l[[i]]
        do.call(add_argset, argset)
      }
      # message(glue::glue("Added {length(l)} argsets to the plan"))
    },
    add_analysis = function(name = uuid::UUIDgenerate(), fn = NULL, fn_name = NULL, ...) {
      stopifnot(is.null(fn) | is.function(fn))
      stopifnot(is.null(fn_name) | is.character(fn_name))

      if (is.null(analyses[[name]])) analyses[[name]] <- list()

      dots <- list(...)
      analyses[[name]] <<- list(fn = fn, fn_name = fn_name)
      analyses[[name]][[argset_name]] <<- dots
    },
    add_analysis_from_df = function(fn = NULL, fn_name = NULL, df) {
      stopifnot(is.null(fn) | is.function(fn) | "fn_name" %in% names(df))
      stopifnot(is.null(fn_name) | is.character(fn_name))

      df <- as.data.frame(df)
      for (i in 1:nrow(df)) {
        argset <- df[i, ]
        argset$fn <- fn
        if (!"fn_name" %in% names(df)) argset$fn_name <- fn_name
        print(argset)
        do.call(add_analysis, argset)
      }
    },
    add_analysis_from_list = function(fn = NULL, fn_name = NULL, l) {
      stopifnot(is.null(fn) | is.function(fn))
      stopifnot(is.null(fn_name) | is.character(fn_name))

      for (i in seq_along(l)) {
        argset <- l[[i]]
        argset$fn <- fn
        if (!"fn_name" %in% names(df)) argset$fn_name <- fn_name
        # message(i)
        do.call(add_analysis, argset)
      }
      # message(glue::glue("Added {length(l)} analyses to the plan"))
    },
    apply_analysis_fn_to_all = function(fn = NULL, fn_name = NULL) {
      stopifnot(is.null(fn) | is.function(fn))
      stopifnot(is.null(fn_name) | is.character(fn_name))

      for (i in seq_along(analyses)) {
        analyses[[i]]$fn <<- fn
        analyses[[i]]$fn_name <<- fn_name
      }
    },
    len = function() {
      length(analyses)
    },
    x_seq_along = function() {
      base::seq_along(analyses)
    },
    set_progress = function(pb) {
      pb_progress <<- pb
    },
    set_progressor = function(pb) {
      pb_progressor <<- pb
    },
    set_verbose = function(x) {
      verbose <<- x
    },
    get_data = function() {
      retval <- list()
      for (i in seq_along(data)) {
        x <- data[[i]]
        if (!is.null(x$fn)) {
          retval[[x$name]] <- x$fn()
        }
        if (!is.null(x$fn_name)) {
          retval[[x$name]] <- do.call(get_anything(x$fn_name))
        }
        if (!is.null(x$direct)) {
          retval[[x$name]] <- x$direct
        }
      }
      if(length(retval)==1){
        if("data__________go_up_one_level" %in% names(retval)){
          retval <- retval$data__________go_up_one_level
        }
      }
      return(retval)
    },
    get_analysis = function(index_analysis) {
      p <- analyses[[index_analysis]]
      p[[argset_name]]$index_analysis <- index_analysis
      return(p)
    },
    get_argset = function(index_analysis) {
      p <- analyses[[index_analysis]][[argset_name]]
      return(p)
    },
    run_one_with_data = function(index_analysis, data, ...) {
      p <- get_analysis(index_analysis)

      if (!is.null(p$fn) & is.null(p$fn_name)) {
        # use fn
        num_args <- length(formals(p$fn))
      } else if (is.null(p$fn) & !is.null(p$fn_name)) {
        # use fn_name
        num_args <- length(formals(get_anything(p$fn_name)))
      }

      args <- list()
      args[["data"]] <- data
      args[[argset_name]] <- p[[argset_name]]

      if (num_args < 2) {
        stop("fn must have at least two arguments")
      } else if (num_args == 2) {
        # dont do anything
      } else {
        dots <- list(...)
        for (i in seq_along(dots)) {
          n <- names(dots)[i]
          args[[n]] <- dots[[i]]
        }
      }

      # actually run it
      if (!is.null(p$fn) & is.null(p$fn_name)) {
        # use fn
        retval <- p$fn(
          data = data,
          p[[argset_name]],
          ...
        )
      } else if (is.null(p$fn) & !is.null(p$fn_name)) {
        # use fn_name
        retval <- do.call(
          what = get_anything(p$fn_name),
          args = args
        )
      }

      return(retval)
    },
    run_one = function(index_analysis, ...) {
      data <- get_data()
      run_one_with_data(index_analysis = index_analysis, data = data, ...)
    },
    use_foreach_decision = function() {
      if (!is.null(self$use_foreach)) {
        return(self$use_foreach)
      } else {
        if (foreach::getDoParWorkers() == 1 | !requireNamespace("progressr", quietly = TRUE)) {
          return(FALSE)
        } else {
          return(TRUE)
        }
      }
    },
    run_all = function(...) {
      # try to deparse important arguments
      dots <- list(...)
      if (".plnr.options" %in% names(dots)) {
        chunk_size <- dots[["chunk_size"]]
      } else {
        chunk_size <- 1
      }
      data <- get_data()

      retval <- vector("list", length = self$len())
      if (!use_foreach_decision()) {
        # running not in parallel
        if (verbose & is.null(pb_progress) & is.null(pb_progressor)) {
          pb_progress <<- progress::progress_bar$new(
            format = paste0("[:bar] :current/:total (:percent) in :elapsedfull, eta: :eta", ifelse(interactive(), "", "\n")),
            clear = FALSE,
            total = self$len()
          )
          pb_progress$tick(0)
          on.exit(pb_progress <<- NULL)
        }

        for (i in x_seq_along()) {
          if (verbose & !is.null(pb_progress)) pb_progress$tick()
          if (verbose & !is.null(pb_progressor)) if(interactive()){
            pb_progressor()
          } else {
            pb_progressor()
          }
          retval[[i]] <- run_one_with_data(index_analysis = i, data = data, ...)
          gc(FALSE)
        }
      } else {
        # running in parallel
        if (verbose & is.null(pb_progress) & is.null(pb_progressor)) {
          progressr::handlers(progressr::handler_progress(
            format = "[:bar] :current/:total (:percent) in :elapsedfull, eta: :eta\n",
            clear = FALSE
          ))
          pb_progressor <<- progressr::progressor(steps = self$len())
          on.exit(pb_progressor <<- NULL)
        }

        retval <- foreach(i = x_seq_along(), .options.future = list(chunk.size = chunk_size)) %dopar% {
          if (verbose & !is.null(pb_progress)) pb_progress$tick()
          if (verbose & !is.null(pb_progressor)) if(interactive()){
            pb_progressor()
          } else {
            pb_progressor()
          }
          run_one_with_data(index_analysis = i, data = data, ...)
          gc(FALSE)
        }
      }

      invisible(retval)
    },
    run_all_progress = function(...) {
      progressr::with_progress(
        {
          run_all(...)
        },
        delay_stdout = F
      )
    }
  )
)

# #' run_all_parallel
# #' @param plan a
# #' @param cores a
# #' @param future.chunk.size Size of future chunks
# #' @param verbose a
# #' @param multisession a
# #' @export
# run_all_parallel <- function(
#   plan,
#   cores = parallel::detectCores(),
#   future.chunk.size = NULL,
#   verbose = interactive(),
#   multisession = TRUE){
#
#   if(multisession){
#     future::plan(future::multisession, workers = cores, earlySignal = TRUE)
#   } else {
#     future::plan(future.callr::callr, workers = cores, earlySignal = TRUE)
#   }
#   on.exit(future:::ClusterRegistry("stop"))
#
#   progressr::handlers(progressr::progress_handler(
#     format = "[:bar] :current/:total (:percent) in :elapsedfull, eta: :eta",
#     clear = FALSE
#     ))
#
#   y <- progressr::with_progress({
#     pb <- progressr::progressor(along = plan$x_seq_along())
#     data <- plan$get_data()
#
#     future.apply::future_lapply(plan$x_seq_along(), function(x) {
#       pb(sprintf("x=%g", x))
#       plan$run_one_with_data(index_arg = x, data = data)
#     }, future.chunk.size = future.chunk.size)
#   })
# }
#'
#' #' Plans
#' #' @import data.table
#' #' @import R6
#' #' @export
#' #' @exportClass Plans
#' Plans <- R6::R6Class(
#'   "Plans",
#'   portable = FALSE,
#'   cloneable = TRUE,
#'   public = list(
#'     list_plan = list(),
#'     initialize = function() {
#'     },
#'     add_plan = function(p) {
#'       list_plan[[length(list_plan) + 1]] <<- Plan$new()
#'
#'       # add data
#'       for (i in seq_along(p$data)) {
#'         list_plan[[length(list_plan)]]$add_data(
#'           fn = p$data[[i]]$fn,
#'           df = p$data[[i]]$df,
#'           name = p$data[[i]]$name
#'         )
#'       }
#'
#'       # add analyses
#'       for (i in seq_along(p$list_arg)) {
#'         arg <- p$list_arg[[i]]$arg
#'         arg$fn <- p$list_arg[[i]]$fn
#'
#'         do.call(list_plan[[length(list_plan)]]$add_analysis, arg)
#'       }
#'     },
#'     add_analysis = function(fn, ...) {
#'       list_arg[[length(list_arg) + 1]] <<- list(
#'         fn = fn,
#'         arg = ...
#'       )
#'     },
#'     len = function(index_plan) {
#'       if (missing(index_plan)) {
#'         return(length(list_plan))
#'       } else {
#'         return(length(list_plan[[index_plan]]))
#'       }
#'     },
#'     x_seq_along = function(index_plan) {
#'       if (missing(index_plan)) {
#'         return(seq_along(list_plan))
#'       } else {
#'         return(seq_along(list_plan[[index_plan]]))
#'       }
#'     },
#'     get_data = function(index_plan) {
#'       list_plan[[index_plan]]$get_data()
#'     },
#'     get_analysis = function(index_plan, index_arg) {
#'       list_plan[[index_plan]]$get_analysis(index_arg)
#'     },
#'     analysis_run = function(data, analysis) {
#'       analysis$fn(
#'         data = data,
#'         arg = analysis$arg
#'       )
#'     }
#'   )
#' )
