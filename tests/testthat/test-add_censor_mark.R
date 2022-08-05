sf1 <- survfit2(Surv(time, status) ~ 1, data = df_lung)
sf2 <- survfit2(Surv(time, status) ~ sex, data = df_lung)
sf3 <- survfit2(Surv(time, status) ~ sex + ph.ecog, data = df_lung)

test_that("add_censor_mark() works with ggsurvfit()", {
  expect_error(
    list(sf1, sf2, sf3) %>%
      lapply(function(x) ggsurvfit(x) + add_censor_mark()),
    NA
  )
})

test_that("add_censor_mark() errors with ggsurvfit()", {
  expect_warning(
    (mtcars %>%
       ggplot2::ggplot(ggplot2::aes(y = mpg, x = hp)) +
       add_censor_mark()) %>%
      print()
  )
})




sf1 <- tidycmprsk::cuminc(Surv(ttdeath, death_cr) ~ 1, data = tidycmprsk::trial)
sf2 <- tidycmprsk::cuminc(Surv(ttdeath, death_cr) ~ trt, data = tidycmprsk::trial)
sf3 <- tidycmprsk::cuminc(Surv(ttdeath, death_cr) ~ trt + grade, data = tidycmprsk::trial)


test_that("add_censor_mark() works with ggcuminc()", {
  expect_error(
    list(sf1, sf2, sf3) %>%
      lapply(function(x) ggcuminc(x) + add_censor_mark()),
    NA
  )
})
