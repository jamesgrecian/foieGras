##' @title calculate one-step-ahead (prediction) residuals from a \code{foieGras} fit
##'
##' @param x a compound \code{fG} tbl fit object
##' @param method method to calculate prediction residuals (default is "oneStepGaussianOffMode"; see `?TMB::oneStepPrediction` for details)
##' @param ... other arguments to TMB::oneStepPrediction
##'
##' @details One-step-ahead residuals are useful for assessing goodness-of-fit in latent variable models. This is a wrapper function for TMB::oneStepPredict (beta version). \code{osar} tries the "fullGaussian" (fastest) method first and falls back to the "oneStepGaussianOffMode" (slower) method for any failures. Subsequent failures are dropped from the output and a warning message is given. Note, OSA residuals can take a considerable time to calculate if there are many individual fits and/or deployments are long. The method is automatically parallelized across 2 x the number of individual fits, up to the number of processor cores available.
##'
##' @references Thygesen, U. H., C. M. Albertsen, C. W. Berg, K. Kristensen, and A. Neilsen. 2017. Validation of ecological state space models using the Laplace approximation. Environmental and Ecological Statistics 24:317–339.
##'
##' @examples
##' ## generate a fG_ssm fit object (call is for speed only)
##' xs <- fit_ssm(sese2, spdf=FALSE, model = "rw", time.step=72, 
##' control = ssm_control(se = FALSE, verbose = 0))
##' 
##' ## just use one seal to save time
##' dres <- osar(xs[2,])
##'
##' @importFrom dplyr "%>%" select slice mutate bind_rows everything
##' @importFrom tibble as_tibble
##' @importFrom TMB oneStepPredict
##' @importFrom parallel stopCluster
##' @export

osar <- function(x, method = "fullGaussian", ...)
{

  map_fn <- function(f, method) {
    oneStepPredict(obj = f$tmb,
                   observation.name = "Y",
                   data.term.indicator = "keep",
                   method = method,
                   subset = which(rep(f$isd, each = 2)),
                   discrete = FALSE,
                   parallel = FALSE,
                   trace = FALSE,
                   ...)
  }

  if(inherits(x, "fG_ssm")) {
    if(nrow(x) > 3 & 
       requireNamespace("future", quietly = TRUE) &
       requireNamespace("furrr", quietly = TRUE)
       ) {
    cat("running in parallel, this could take a while...\n")
    cl <- future::makeClusterPSOCK(availableCores())
    future::plan(cluster, workers = cl)
    
    r <- x$ssm %>%
      furrr::future_map(~ try(map_fn(.x, method), silent = TRUE), 
                 .options = furrr::furrr_options(seed = TRUE))
    
    stopCluster(cl)
    } else {
      if(nrow(x) > 3) cat("future and furrr packages not installed for parallel processing, 
                           running sequentially. This could take a while...\n")
      r <- lapply(1:nrow(x), function(i) {
        try(map_fn(x$ssm[[i]], method), silent = TRUE)
    })
    }
  } else {
    stop("a foieGras ssm fit object with class fG_ssm is required")
  }
  
  cr <- sapply(r, function(.) inherits(., "try-error"))

  ## if any try-errors then retry using oneStepGaussianOffMode but preserve successful results
  if (any(cr)) {
    ## re-try on failures
    redo <- x[which(cr), ]
    if(nrow(x) > 3 & 
       requireNamespace("future", quietly = TRUE) &
       requireNamespace("furrr", quietly = TRUE)
    ) {
      cat("running in parallel, this could take a while...\n")
      cl <- future::makeClusterPSOCK(availableCores())
      future::plan(cluster, workers = cl)
      
      r.redo <- redo$ssm %>%
        furrr::future_map(~ try(map_fn(.x, method = "oneStepGaussianOffMode")), 
                   .options = furrr::furrr_options(seed = TRUE))
      
      stopCluster(cl)
    } else {
      if(nrow(x) > 3) cat("future and furrr packages not installed for parallel processing, 
                           running sequentially. This could take a while...\n")
      r.redo <- lapply(1:nrow(redo), function(i) {
        try(map_fn(redo$ssm[[i]], method = "oneStepGaussianOffMode"), silent = TRUE)
      })
    }
    ## check for repeat failures & throw warning but preserve all successful results
    cr.redo <- sapply(r.redo, function(.) inherits(., "try-error"))
    if (any(cr.redo)) {
      warning(
        sprintf(
          "\n failed to calculate OSA residuals for the following individuals: %s \n",
          x$id[which(cr.redo)]
        ), immediate. = TRUE, call. = FALSE
      )
    r.redo <- r.redo[-which(cr.redo)]  
    }
    
    ## combine original successes with redo successes
    if(length(r.redo) > 0) r[which(cr)] <- r.redo
    else {
     r <- r[-which(cr)]
    }
  }

  ## return error if no successful results, otherwise return OSA resid object
  if (length(r) == 0) {
    stop("no residuals calculated", call. = FALSE)
  } else {
    out <- lapply(1:length(r), function(i) {
      z <- r[[i]] %>%
        mutate(id = x$id[i]) %>%
        select(id, everything())
      x.z <- z %>% slice(seq(1, nrow(z), by = 2))
      y.z <- z %>% slice(seq(2, nrow(z), by = 2))
      date <- x$ssm[[i]]$fitted$date
      bind_rows(data.frame(date, x.z), data.frame(date, y.z)) %>%
        mutate(coord = rep(c("x", "y"), each = nrow(z) / 2))
    }) 
    
    out <- lapply(out, function(x) {
        x[, c("id", "date", "residual", "coord")]
      }) %>% 
      do.call(rbind, .) %>% 
      as_tibble() 

    class(out) <- append("fG_osar", class(out))
    return(out)
  }
}
