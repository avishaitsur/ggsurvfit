test_that("stat_stepribbon() works", {
  expect_error(
    gg_stepribbon1 <-
      survfit(Surv(time, status) ~ 1, df_lung) %>%
      broom::tidy() %>%
      ggplot2::ggplot(ggplot2::aes(x = time, y = estimate, ymin = conf.low, ymax = conf.high)) +
      ggplot2::geom_step() +
      stat_stepribbon(alpha = 0.2),
    NA
  )

  vdiffr::expect_doppelganger("gg_stepribbon1", gg_stepribbon1)

  expect_error(
    gg_stepribbon2 <-
      survfit(Surv(time, status) ~ 1, df_lung) %>%
      broom::tidy() %>%
      ggplot2::ggplot(ggplot2::aes(x = time, y = estimate, ymin = conf.low, ymax = conf.high)) +
      ggplot2::geom_step() +
      stat_stepribbon(alpha = 0.2, direction = "vh"),
    NA
  )

  vdiffr::expect_doppelganger("gg_stepribbon2", gg_stepribbon2)
})