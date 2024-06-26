% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ggsurvfit.R
\name{ggsurvfit}
\alias{ggsurvfit}
\title{Plot Survival Probability}
\usage{
ggsurvfit(
  x,
  type = "survival",
  linetype_aes = FALSE,
  theme = theme_ggsurvfit_default(),
  ...
)
}
\arguments{
\item{x}{a 'survfit' object created with \code{survfit2()}}

\item{type}{type of statistic to report.
Available for Kaplan-Meier estimates only.
Default is \code{"survival"}.
Must be one of the following or a function:\tabular{ll}{
   type \tab transformation \cr
   \code{"survival"} \tab \code{x} \cr
   \code{"risk"} \tab \code{1 - x} \cr
   \code{"cumhaz"} \tab \code{-log(x)} \cr
   \code{"cloglog"} \tab \code{log(-log(x))} \cr
}}

\item{linetype_aes}{logical indicating whether to add \code{ggplot2::aes(linetype = strata)}
to the \code{ggplot2::geom_step()} call. When strata are present, the resulting figure
will be a mix a various line types for each stratum.}

\item{theme}{a survfit theme. Default is \code{theme_ggsurvfit_default()}}

\item{...}{arguments passed to \code{ggplot2::geom_step(...)}, e.g. \code{size = 2}}
}
\value{
a ggplot2 figure
}
\description{
Plot survival probabilities (and other transformations) using the results
from \code{survfit2()} or \code{survival::survfit()}; although, the former is recommend
to have the best experience with the \strong{ggsurvfit} package.
}
\section{Details}{


This function creates a ggplot figure from the 'survfit' object.
To better understand how to modify the figure, review the simplified
code used internally:

\if{html}{\out{<div class="sourceCode r">}}\preformatted{survfit2(Surv(time, status) ~ sex, data = df_lung) \%>\%
  tidy_survfit() \%>\%
  ggplot(aes(x = time, y = estimate,
             min = conf.low, ymax = conf.low,
             color = strata, fill = strata)) +
  geom_step()
}\if{html}{\out{</div>}}
}

\examples{
# Default publication ready plot
survfit2(Surv(time, status) ~ sex, data = df_lung) \%>\%
  ggsurvfit() +
  scale_ggsurvfit(x_scales = list(breaks = seq(0, 30, by = 6)))

# Changing statistic type
survfit2(Surv(time, status) ~ sex, data = df_lung) \%>\%
  ggsurvfit(type = "cumhaz")

# Configuring KM line type to vary by strata
survfit2(Surv(time, status) ~ sex, data = df_lung) \%>\%
  ggsurvfit(linetype_aes = TRUE) +
  scale_ggsurvfit()

# Customizing the plot to your needs
survfit2(Surv(time, status) ~ 1, data = df_lung) \%>\%
  ggsurvfit() +
  add_censor_mark() +
  add_confidence_interval() +
  add_quantile() +
  add_risktable() +
  scale_ggsurvfit()
}
\seealso{
Visit the \href{https://www.danieldsjoberg.com/ggsurvfit/articles/gallery.html}{gallery} for examples modifying the default figures
}
