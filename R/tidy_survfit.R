#' Tidy a survfit object
#'
#' The broom package exports a tidier for `"survfit"` objects.
#' This function adds on top of that and returns more information.
#' The function also utilizes additional information stored when the
#' survfit object is created with `survfit2()`.
#' It's recommended to always use this function with `survfit2()`.
#'
#' @param x a 'survfit' object created with `survfit2()`
#' @param times numeric vector of times. Default is `NULL`,
#' which returns all observed times.
#' @param type type of statistic to report.
#' Available for Kaplan-Meier estimates only.
#' Default is `"survival"`.
#' Must be one of the following or a function:
#' ```{r, echo = FALSE}
#' dplyr::tribble(
#'   ~type,          ~transformation,
#'   '`"survival"`', '`x`',
#'   '`"risk"`',     '`1 - x`',
#'   '`"cumhaz"`',   '`-log(x)`',
#'   '`"cloglog"`',   '`log(-log(x))`',
#' ) %>%
#' knitr::kable()
#' ```
#'
#' @return a tibble
#' @export
#'
#' @examples
#' survfit2(Surv(time, status) ~ factor(ph.ecog), data = df_lung) %>%
#'   tidy_survfit()
tidy_survfit <- function(x,
                         times = NULL,
                         type = c("survival", "risk", "cumhaz", "cloglog")) {
  # check inputs ---------------------------------------------------------------
  if (!inherits(x, "survfit")) {
    cli_abort(c("!" = "Argument {.code x} must be class {.cls survfit}.",
                "i" = "Create the object with {.code survfit2()}"))
  }
  if (inherits(x, "survfitms")) type <- "cuminc"
  else if (is.character(type)) type <- match.arg(type)


  # create base tidy tibble ----------------------------------------------------
  if (is.null(x$start.time) && min(x$time) < 0) {
    cli::cli_inform(c(
      "!" ="Setting start time to {.val {min(x$time)}}.",
      "i" = "Specify {.code ggsurvfit::survfit2(start.time)} to override this default."
    ))
  }
  df_tidy <-
    survival::survfit0(x) %>%
    broom::tidy()

  # if a competing risks model, filter on the outcome of interest
  if (inherits(x, "survfitms")) {
    df_tidy <-
      df_tidy %>%
      dplyr::filter(!.data$state %in% "(s0)") %>%
      dplyr::select(-dplyr::all_of(c("n.risk", "n.censor"))) %>%
      dplyr::left_join(
        df_tidy %>% dplyr::filter(.data$state %in% "(s0)") %>% dplyr::select(dplyr::any_of(c("strata", "time", "n.risk", "n.censor"))),
        by = intersect(c("strata", "time"), names(df_tidy))
      ) %>%
      dplyr::relocate(dplyr::any_of(c("n.risk", "n.censor")), .after = "time") %>%
      dplyr::rename(outcome = "state")
  }

  # if times are specified, add them (and associated stats) to the data frame
  df_tidy <- .add_tidy_times(df_tidy, times = times)

  # adding cumulative events and censor
  df_tidy <- .add_cumulative_stats(df_tidy)

  # if times are specified, remove the un-selected times and correct the
  # n.censor and n.event stats (these are cumulative over the time
  # interval, between specified times)
  df_tidy <- .keep_selected_times(df_tidy, times = times)

  # transform survival estimate as specified
  df_tidy <- .transform_estimate(df_tidy, type = type, survfit = x)

  # improve strata label, if possible
  df_tidy <- .construct_strata_label(df_tidy, survfit = x)

  # return tidied tibble
  df_tidy %>%
    dplyr::select(-"time_max") %>%
    dplyr::mutate(
      conf.level = x$conf.int
    )
}


.construct_strata_label <- function(x, survfit) {
  # if no strata, then return without adding strata label
  if (!"strata" %in% names(x)) {
    return(x)
  }

  # if not a survift2 object, do not attempt to extract information from survfit object
  if (!inherits(survfit, c("survfit2", "tidycuminc"))) {
    x$strata_label <- "strata"
    # make the stratum a factor so it will sort properly later
    x$strata <- factor(x$strata, levels = unique(x$strata))
    return(x)
  }

  # first extract needed item from survfit call
  if (inherits(survfit, "survfit2")) {
    formula <- .extract_formula_from_survfit(survfit)
    data <- .extract_data_from_survfit(survfit)
  }
  else if (inherits(survfit, "tidycuminc")) {
    formula <- survfit$formula
    data <- survfit$data
  }

  # get a list of the stratum variables
  formula_rhs <- formula
  rlang::f_lhs(formula_rhs) <- NULL
  strata_model_frame <-
    tryCatch(
      stats::model.frame(formula = formula_rhs, data = data),
      error = function(e) NULL
    )
  strata_variables <- names(strata_model_frame)

  # construct strata label -----------------------------------------------------
  if (is.null(strata_variables)) {
    x$strata_label <- all.vars(formula_rhs) %>% paste(collapse = ", ")
  } else {
    x$strata_label <-
      lapply(
        strata_variables,
        function(x) attr(data[[x]], "label") %||% x
      ) %>%
      unlist() %>%
      paste(collapse = ", ")
  }

  # attempt to clean up the strata values by removing 'VARNAME='
  for (v in seq_len(length(strata_variables))) {
    if (v == 1L) {
      x$strata <-
        sub(
          pattern = paste0("^", .escape_regex_chars(strata_variables[v]), "\\="),
          replacement = "",
          x = x$strata
        )
    } else {
      x$strata <-
        sub(
          pattern = paste0(", ", strata_variables[v], "="),
          replacement = ", ",
          x = x$strata,
          fixed = TRUE
        )
    }
  }

  # make the stratum a factor so it will sort properly later
  x$strata <- factor(x$strata, levels = unique(x$strata))

  # return tidy tibble
  x
}

.escape_regex_chars <- function(x) {
  gsub(pattern = "(\\W)", replacement = "\\\\\\1", x = x)
}

.transform_estimate <- function(x, type, survfit) {
  # select transformation function ---------------------------------------------
  if (rlang::is_string(type)) {
    .transfun <-
      switch(type,
             survival = function(y) y,
             cuminc = function(y) y,
             risk = function(y) 1 - y,
             # survfit object contains an estimate for Cumhaz and SE based on Nelson-Aalen with or without correction for ties
             # However, no CI is calculated automatically. For plotting, the MLE estimator is used for convenience.
             cumhaz = function(y) -log(y),
             cloglog = function(y) log(-log(y))
      )
  } else {
    .transfun <- type
  }
  if (!rlang::is_function(.transfun)) {
    cli_abort("The {.var type} argument must be one of {.val {c('survival', 'risk', 'cumhaz', 'cloglog')}}, or a function.")
  }

  # transform estimates --------------------------------------------------------
  x <-
    x %>%
    dplyr::mutate(
      dplyr::across(dplyr::any_of(c("estimate", "conf.low", "conf.high")), .transfun)
    )

  # add estimate type metadata -------------------------------------------------
  x <-
    x %>%
    dplyr::mutate(
      estimate_type =
        ifelse(
          rlang::is_string(.env$type),
          .env$type,
          rlang::expr_deparse(.transfun)
        ),
      estimate_type_label =
        dplyr::case_when(
          rlang::is_string(.env$type) && .env$type %in% "survival" ~ "Survival Probability",
          rlang::is_string(.env$type) &&
            .env$type %in% "cuminc" &&
            !is.null(.env$survfit$transitions) &&
            sum(apply(.env$survfit$transitions, MARGIN = 1, FUN = sum) > 0L) == 1L ~ "Cumulative Incidence",
          rlang::is_string(.env$type) &&
            .env$type %in% "cuminc" &&
            !is.null(.env$survfit$transitions) ~ "Probability in State",
          rlang::is_string(.env$type) && .env$type %in% "risk" ~ "Risk",
          rlang::is_string(.env$type) && .env$type %in% "cumhaz" ~ "Cumulative Hazard",
          rlang::is_string(.env$type) && .env$type %in% "cloglog" ~ "Log Minus Log Survival",
          TRUE ~ rlang::expr_deparse(.transfun)
        )
    )

  # adding the monotonicity
  x <- .add_monotonicity_type(x, type = type)

  # switch conf.low and conf.high levels if needed
  if (x$monotonicity_type[1] %in% "increasing" && all(c("conf.low", "conf.high") %in% colnames(x))) {
    x <- dplyr::rename(x, conf.low = "conf.high", conf.high = "conf.low")
  }

  # return data frame ----------------------------------------------------------
  x
}

.keep_selected_times <- function(x, times) {
  if (is.null(times)) {
    return(x)
  }

  x %>%
    dplyr::mutate(
      time_group = cut(.data$time, breaks = union(.env$times, max(.env$x$time)))
    ) %>%
    dplyr::group_by(dplyr::across(dplyr::any_of(c("time_group", "strata", "outcome")))) %>%
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(c("n.censor", "n.event")),
        ~ sum(.)
      )
    ) %>%
    dplyr::filter(.data$time %in% .env$times) %>%
    dplyr::ungroup() %>%
    dplyr::select(-"time_group")
}

.add_cumulative_stats <- function(x) {
  x %>%
    dplyr::group_by(dplyr::across(dplyr::any_of(c("strata", "outcome")))) %>%
    dplyr::mutate(
      cum.event = cumsum(.data$n.event),
      cum.censor = cumsum(.data$n.censor),
      .after = "n.censor"
    ) %>%
    dplyr::ungroup()
}

.add_tidy_times <- function(x, times) {
  x <-
    x %>%
    dplyr::group_by(dplyr::across(dplyr::any_of(c("strata", "outcome")))) %>%
    dplyr::mutate(
      time_max = max(.data$time)
    ) %>%
    dplyr::ungroup()

  if (is.null(times)) {
    return(x)
  }

  # create tibble of times
  df_times <-
    do.call(
      what = expand.grid,
      args =
        # remove NULL elements before passing to exapnd grid
        Filter(
          Negate(is.null),
          list(
            time = times,
            strata = suppressWarnings(unique(x$strata)),
            outcome = suppressWarnings(unique(x$outcome)),
            stringsAsFactors = FALSE
          )
        )
    )

  # merge tibble of times with tidy df
  df_result <-
    dplyr::full_join(
      x,
      df_times,
      by = intersect(c("time", "strata", "outcome"), names(x))
    ) %>%
    dplyr::arrange(dplyr::across(dplyr::any_of(c("outcome", "strata", "time"))))

  # fill in missing stats
  df_result <-
    df_result %>%
    dplyr::group_by(dplyr::across(dplyr::any_of(c("strata", "outcome")))) %>%
    dplyr::mutate(
      dplyr::across(c("n.event", "n.censor"), ~ ifelse(is.na(.), 0, .))
    ) %>%
    tidyr::fill(
      -c("n.risk", "n.event", "n.censor"),
      .direction = "down"
    ) %>%
    tidyr::fill(
      "n.risk",
      .direction = "up"
    ) %>%
    dplyr::mutate(
      n.risk = ifelse(.data$time > .data$time_max, 0, .data$n.risk)
    ) %>%
    dplyr::ungroup()

  # any times above the max observed time are set to NA
  df_result %>%
    dplyr::mutate(
      dplyr::across(
        dplyr::any_of(c("estimate", "std.error", "conf.low", "conf.high")),
        ~ ifelse(.data$time > .data$time_max, NA, .)
      )
    )
}

.add_monotonicity_type <- function(x, type = NULL, estimate_var = "estimate") {
  if ("monotonicity_type" %in% names(x)) {
    return(x)
  }

  # adding the monotonicity, if a known type
  if (rlang::is_string(type)) {
    x$monotonicity_type <-
      switch(type,
             "survival" = "decreasing",
             "cuminc" = "increasing",
             "risk" = "increasing",
             "cumhaz" = "increasing",
             "cloglog" = "increasing"
      )
  }
  else {
    x <-
      x %>%
      dplyr::group_by(dplyr::across(dplyr::any_of("group"))) %>%
      dplyr::mutate(
        monotonicity_type =
          dplyr::case_when(
            .data[[estimate_var]][1] > .data[[estimate_var]][dplyr::n()] ~ "decreasing",
            .data[[estimate_var]][1] < .data[[estimate_var]][dplyr::n()] ~ "increasing"
          )
      ) %>%
      dplyr::ungroup()
  }

  x
}
