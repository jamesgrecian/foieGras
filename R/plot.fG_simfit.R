##' @title plot
##'
##' @description visualize tracks simulated from a foieGras model fit
##'
##' @param x a \code{foieGras} simulation data.frame with class \code{fG_simfit}
##' @param type plots tracks as "line", "points" or "both" (default). 
##' @param zoom logical; should map extent be defined by track extent (TRUE) or 
##' should global map be drawn (FALSE; default).  
##' @param or orientation of projected map, default is to centre on 
##' start of fitted track (ignored if \code{mapproj} package is not installed).
##' @param ncol number of columns to arrange multiple plots
##' @param pal \code{hcl.colors} palette to use (default: "Viridis"; type 
##' \code{hcl.pals()} for options)
##' @param ... additional arguments to be ignored
##' 
##' @return Plots of simulated tracks. 
##' 
##' @importFrom ggplot2 ggplot aes geom_point geom_path theme_minimal
##' @importFrom ggplot2 element_blank xlab ylab geom_polygon 
##' @importFrom ggplot2 coord_map coord_quickmap theme_void
##' @importFrom broom tidy
##' @importFrom patchwork wrap_plots
##' @importFrom grDevices hcl.colors extendrange
##' @importFrom rnaturalearth ne_countries
##' @method plot fG_simfit
##'
##' @examples
##' fit <- fit_ssm(sese1, vmax = 4, model = "crw", time.step = 72)
##' trs <- simfit(fit, what = "p", reps = 2)
##' plot(trs, type = "b")
##'
##' @export

plot.fG_simfit <- function(x, 
                           type = c("lines","points","both"),
                           zoom = FALSE,
                           or = NULL,
                           ncol = 1,
                           pal = "Viridis",
                        ...)
{
  if (length(list(...)) > 0) {
    warning("additional arguments ignored")
  }
  
  type <- match.arg(type)
  
  ## get worldmapAs the estimation of $\gamma_t$ is sensitive to choice of time scale, we examined the influence of different prediction intervals (1 - 20 min) on the ability of the movement persistence model to resolve changes in movement pattern along the penguin tracks.
  if(requireNamespace("rnaturalearthdata", quietly = TRUE)) {
    wm <- ne_countries(scale = 50, returnclass = "sp")
  } else {
    wm <- ne_countries(scale = 110, returnclass = "sp")
  }
  wm <- suppressMessages(tidy(wm))
  wm$region <- wm$id
  wm.df <- wm[,c("long","lat","group","region")]
  
  ## do plots
  p <- lapply(x$sims, function(x) {
    if(min(x$lon) < -175 & max(x$lon > 175)) {
      x$lon <- ifelse(x$lon < 0, x$lon + 360, x$lon)
    }

    if(!zoom) { 
      bounds <- c(-180,180,-89.99,89.99)
    } else {
      bounds <- c(range(x$lon), range(x$lat))
    }
 
    if(is.null(or)) or <- c(x$lat[1], x$lon[1], 0)
    
      m <- ggplot() + 
        geom_polygon(data = wm.df, 
                     aes(long, lat, group = group), 
                     fill = grey(0.4))
      
      if(requireNamespace("mapproj", quietly = TRUE)) {
        m <- m + coord_map("ortho",
                  orientation = or,
                  xlim = bounds[1:2],
                  ylim = bounds[3:4])
      } else {
        m <- m + coord_quickmap(
          xlim = bounds[1:2],
          ylim = bounds[3:4]
        )
      }
    
    switch(type, 
           lines = {
             m <- m + 
               geom_path(data = subset(x, rep != 0),
                         aes(lon, lat, group = rep),
                         colour = hcl.colors(n=5, palette = pal)[1],
                         size = 0.5,
                         alpha = 0.6
                         )
           },
           points = {
             m <- m + 
               geom_point(data = subset(x, rep != 0),
                          aes(lon, lat),
                          colour = hcl.colors(n=5, palette = pal)[1],
                          size = 0.75,
                          alpha = 0.6)
           },
           both = {
             m <- m + 
               geom_path(data = subset(x, rep != 0),
                         aes(lon, lat, group = rep),
                         colour = hcl.colors(n=5, palette = pal)[1],
                         size = 0.5,
                         alpha = 0.6
               ) +
               geom_point(data = subset(x, rep != 0),
                          aes(lon, lat),
                          colour = hcl.colors(n=5, palette = pal)[1],
                          size = 0.75,
                          alpha = 0.6)
           })
    m <- m + 
      geom_point(
        data = subset(x, rep == 0),
        aes(lon, lat),
        colour = hcl.colors(n=5, palette = pal)[3],
        size = 1
      ) +
      xlab(element_blank()) +
      ylab(element_blank()) + 
      theme_void()
      
  })
  ## arrange plots
  wrap_plots(p, ncol = ncol, heights = rep(1, ceiling(length(p)/ncol)))
}
  