##' generate error ellipses from x,y coordinates, semi-major, semi-minor axes and ellipse orientation
##' 
##' @param x x-coordinate, usually in projected units (km)
##' @param y y-coordinate, usually in projected units (km)
##' @param a ellipse semi-major axis (km)
##' @param b ellipse semi-minor axis (km)
##' @param theta ellipse orientation from north (degrees)
##'
##' @keywords internal

elps <- function(x, y, a, b, theta = 90, conf = TRUE) {
  m <- ifelse(!conf, 1, 1.96)
  ln <- seq(0, 2*pi, l = 50)
  theta <- (-1 * theta + 90) / 180 * pi   ## req'd rotation to get 0 deg pointing N
  x1 <- m * a * cos(theta) * cos(ln) - m * b * sin(theta) * sin(ln)
  y1 <- m * a * sin(theta) * cos(ln) + m * b * cos(theta) * sin(ln)
  
  cbind(c(x+x1, x+x1[1]), c(y+y1, y+y1[1]))
}


##' @title plot
##'
##' @description visualize fits from an fG_ssm object
##'
##' @param x a \code{foieGras} ssm fit object with class `fG_ssm`
##' @param what specify which location estimates to display on time-series plots: fitted or predicted
##' @param type of plot to generate: 1-d time series for lon and lat separately (type = 1, default) or 2-d track plot (type = 2)
##' @param outlier include outlier locations dropped by prefilter (outlier = TRUE, default)
##' @param pages each individual is plotted on a separate page by default (pages = 0), 
##' multiple individuals can be combined on a single page; pages = 1
##' @param ncol number of columns to arrange plots when combining individuals on a single page (ignored if pages = 0)
##' @param ask logical; if TRUE (default) user is asked for input before each plot is rendered. set to FALSE to return ggplot objects
##' @param pal \code{hcl.colors} palette to use (default: "Zissou1"; type \code{hcl.pals()} for options)
##' @param ... additional arguments to be ignored
##' 
##' @return a ggplot object with either: (type = 1) 1-d time series of fits to data, 
##' separated into x and y components (units = km) with prediction uncertainty ribbons (2 x SE); 
##' or (type = 2) 2-d fits to data (units = km)
##' 
##' @importFrom ggplot2 ggplot geom_point geom_path aes_string ggtitle geom_rug theme_minimal vars labs
##' @importFrom ggplot2 element_text element_blank xlab ylab labeller label_both label_value geom_ribbon facet_wrap
##' @importFrom tidyr gather
##' @importFrom sf st_multipolygon st_polygon st_as_sfc st_as_sf
##' @importFrom patchwork wrap_plots
##' @importFrom grDevices hcl.colors devAskNewPage
##' @method plot fG_ssm
##'
##' @examples
##' ## generate a fG_ssm fit object (call is for speed only)
##' xs <- fit_ssm(sese2, spdf=FALSE, model = "rw", time.step=72, 
##' control = ssm_control(se = FALSE, verbose = 0))
##' 
##' plot(xs, what = "f", type = 1)
##' plot(xs, what = "p", type = 2)
##'
##' @export

plot.fG_ssm <-
  function(x,
           what = c("fitted", "predicted"),
           type = 1,
           outlier = TRUE,
           pages = 0,
           ncol = 1,
           ask = TRUE,
           pal = "Zissou1",
           ...)
  {
    if (length(list(...)) > 0) {
      warning("additional arguments ignored")
    }
    
    what <- match.arg(what)
    
    wpal <- hcl.colors(n = 5, palette = pal)
    
    if (inherits(x, "fG_ssm")) {
      switch(what,
             fitted = {
               ssm <- grab(x, "fitted", as_sf = FALSE)
             },
             predicted = {
               if (any(sapply(x$ssm, function(.)
                 is.na(.$ts)))) {
                 ssm <- grab(x, "fitted", as_sf = FALSE)
                 warning(
                   "there are no predicted locations because you used time.step = NA when calling `fit_ssm`, plotting fitted locations instead",
                   call. = FALSE
                 )
               } else {
                 ssm <- grab(x, "predicted", as_sf = FALSE)
               }
             })
      
      if (outlier) {
        d <- grab(x, "data", as_sf = FALSE)
        d$lc <- with(d, factor(
          lc,
          levels = c("3", "2", "1", "0", "A", "B", "Z"),
          ordered = TRUE
        ))
      } else {
        d <- grab(x, "data", as_sf = FALSE)
        d$lc <- with(d, factor(
            lc,
            levels = c("3", "2", "1", "0", "A", "B", "Z"),
            ordered = TRUE
          ))
        d <- subset(d, keep)
      }
      
      if (type == 1) {
        foo <- ssm[, c("id","x","y")]
        foo <- gather(foo, key = "coord", value = "value", x, y)
        foo.se <- ssm[, c("x.se", "y.se")] 
        foo.se <- gather(foo.se, key = "coord.se", value = "se", x.se, y.se)
        bar <- data.frame(date = rep(ssm$date, 2))

        foo.d <- d[, c("id","x","y")]
        foo.d <- gather(foo.d, key = "coord", value = "value", x, y)
        bar.d <- rbind(d[, c("date", "lc", "keep")], d[, c("date", "lc", "keep")])
        
        pd <- cbind(foo, foo.se, bar)[, c("id", "date", "coord", "value", "se")]
        dd <- cbind(foo.d, bar.d)[, c("id", "date", "lc", "coord", "value", "keep")]
        
        ## coerce to lists
        pd.lst <- split(pd, pd$id)
        dd.lst <- split(dd, dd$id)
        
        p <- lapply(1:nrow(x), function(i) {
          px <- ggplot(subset(dd.lst[[i]], keep),
                       aes(date, value))
          ## add ribbon
          px <- px + geom_ribbon(
              data = pd.lst[[i]],
              aes(date, ymin = value - 2 * se,
                  ymax = value + 2 * se),
              fill = wpal[5],
              alpha = 0.4
            )
          
          if (outlier) {
            px <- px +
              geom_point(
                data = subset(dd.lst[[i]], !keep),
                aes(date, value),
                colour = wpal[4],
                shape = 4
              ) +
              geom_point(
                data = subset(dd.lst[[i]], keep),
                aes(date, value),
                colour = wpal[1],
                shape = 19,
                size = 2
              ) +
              geom_rug(
                data = subset(dd.lst[[i]], !keep),
                aes(date),
                colour = wpal[4],
                sides = "b"
              ) +
              geom_rug(
                data = subset(dd.lst[[i]], keep),
                aes(date),
                colour = wpal[1],
                sides = "b"
              )
          } else {
            px <- px +
              geom_point(
                data = subset(dd.lst[[i]], keep),
                aes(date, value),
                colour = wpal[1],
                shape = 19,
                size = 2
              ) +
              geom_rug(
                data = subset(dd.lst[[i]], keep),
                aes(date),
                colour = wpal[1],
                sides = "b"
              )
          }
          px <- px +
            geom_point(
              data = pd.lst[[i]],
              aes(date, value),
              col = wpal[5],
              shape = 20,
              size = 0.75
            ) +
            facet_wrap(
              facets = vars(coord),
              scales = "free",
              labeller = labeller(coord = label_value),
              ncol = 2
            ) +
            labs(title = paste("id:", x$id[i])) +
            xlab(element_blank()) +
            ylab(element_blank()) +
            theme_minimal()
          px
        })
        names(p) <- x$id
        
        if (!pages) {
          if(ask) {
            devAskNewPage(ask = TRUE)
            print(p)
            devAskNewPage(ask = FALSE)
          } else {
            return(p)
          }
        } else if (pages) {
          wrap_plots(p, ncol = ncol, byrow = TRUE)
        }
        
      } else if (type == 2) {
        ssm.lst <- split(ssm, ssm$id)
        conf_poly <- lapply(ssm.lst, function(x) {
          conf <- lapply(1:nrow(x), function(i)
            with(x, elps(x[i], y[i], x.se[i], y.se[i], 90)))
          tmp <- lapply(conf, function(x)
            st_polygon(list(x)))
          st_multipolygon(tmp)
        })

        conf_sf <- st_as_sf(st_as_sfc(conf_poly)) 
        conf_sf$id <- unique(ssm$id)
        
        d.lst <- split(d, d$id)
        ssm.lst <- split(ssm, ssm$id)
        
        p <- lapply(1:nrow(x), function(i) {
          m <- ggplot() +
            geom_sf(
              data = subset(conf_sf, id == unique(id)[i]),
              col = NA,
              fill = wpal[5],
              alpha = 0.25
            )
          
          if (outlier) {
            m <- m +
              geom_point(
                data = subset(d, !keep & id == unique(id)[i]),
                aes(x, y),
                size = 1,
                colour = wpal[4],
                shape = 4
              ) +
              geom_point(
                data = subset(d, keep & id == unique(id)[i]),
                aes(x, y),
                size = 2,
                colour = wpal[1],
                shape = 19,
                alpha = 0.6
              )
          } else {
            m <- m +
              geom_point(
                data = subset(d, keep & id == unique(id)[i]),
                aes(x, y),
                size = 2,
                colour = wpal[1],
                shape = 19,
                alpha = 0.6
              )
          }
          m <- m +
            geom_path(
              data = subset(ssm, id == unique(id)[i]),
              aes(x, y),
              col = wpal[5],
              lwd = 0.2
            ) +
            geom_point(
              data = subset(ssm, id == unique(id)[i]),
              aes(x, y),
              col = wpal[5],
              shape = 20,
              size = 0.75
            ) +
            labs(title = paste("id:", x[i, "id"]))
          
          m <- m +
            xlab(element_blank()) +
            ylab(element_blank()) +
            theme_minimal()
          m
        })
        names(p) <- x$id
        if (!pages) {
          if(ask) {
            devAskNewPage(ask = TRUE)
            print(p)
            devAskNewPage(ask = FALSE)
          } else {
            return(p)
          }
        } else if (pages) {
          wrap_plots(p, ncol = ncol, heights = rep(1, ceiling(length(p) / ncol)))
        }
      }
    } else {
      stop("x must be a fG_ssm tibble")
    }
}
