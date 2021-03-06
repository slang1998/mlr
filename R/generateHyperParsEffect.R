#' @title Generate hyperparameter effect data.
#'
#' @description
#' Generate cleaned hyperparameter effect data from a tuning result or from a
#' nested cross-validation tuning result. The object returned can be used for
#' custom visualization or passed downstream to an out of the box mlr method,
#' \code{\link{plotHyperParsEffect}}.
#'
#' @param tune.result [\code{\link{TuneResult}} | \code{\link{ResampleResult}}]\cr
#'  Result of \code{\link{tuneParams}} (or \code{\link{resample}} ONLY when used
#'  for nested cross-validation). The tuning result (or results if the
#'  output is from nested cross-validation), also containing the
#'  optimizer results. If nested CV output is passed, each element in the list
#'  will be considered a separate run, and the data from each run will be
#'  included in the dataframe within the returned \code{HyperParsEffectData}.
#' @param include.diagnostics [\code{logical(1)}]\cr
#'  Should diagnostic info (eol and error msg) be included?
#'  Default is \code{FALSE}.
#' @param trafo [\code{logical(1)}]\cr
#'  Should the units of the hyperparameter path be converted to the
#'  transformed scale? This is only useful when trafo was used to create the
#'  path.
#'  Default is \code{FALSE}.
#'
#' @return [\code{HyperParsEffectData}]
#'  Object containing the hyperparameter effects dataframe, the tuning
#'  performance measures used, the hyperparameters used, a flag for including
#'  diagnostic info, a flag for whether nested cv was used, and the optimization
#'  algorithm used.
#'
#' @examples \dontrun{
#' # 3-fold cross validation
#' ps = makeParamSet(makeDiscreteParam("C", values = 2^(-4:4)))
#' ctrl = makeTuneControlGrid()
#' rdesc = makeResampleDesc("CV", iters = 3L)
#' res = tuneParams("classif.ksvm", task = pid.task, resampling = rdesc,
#' par.set = ps, control = ctrl)
#' data = generateHyperParsEffectData(res)
#' plotHyperParsEffect(data, x = "C", y = "mmce.test.mean")
#'
#' # nested cross validation
#' ps = makeParamSet(makeDiscreteParam("C", values = 2^(-4:4)))
#' ctrl = makeTuneControlGrid()
#' rdesc = makeResampleDesc("CV", iters = 3L)
#' lrn = makeTuneWrapper("classif.ksvm", control = ctrl,
#'                       resampling = rdesc, par.set = ps)
#' res = resample(lrn, task = pid.task, resampling = cv2,
#'                extract = getTuneResult)
#' data = generateHyperParsEffectData(res)
#' plotHyperParsEffect(data, x = "C", y = "mmce.test.mean", plot.type = "line")
#' }
#' @export
#' @importFrom utils type.convert
generateHyperParsEffectData = function(tune.result, include.diagnostics = FALSE,
                                       trafo = FALSE) {
  assert(
    checkClass(tune.result, "ResampleResult"),
    checkClass(tune.result, classes = "TuneResult")
  )
  assertFlag(include.diagnostics)

  # in case we have nested CV
  if (getClass1(tune.result) == "ResampleResult"){
    if (trafo){
      ops = extractSubList(tune.result$extract, "opt.path", simplify = FALSE)
      ops = lapply(ops, trafoOptPath)
      op.dfs = lapply(ops, as.data.frame)
      op.dfs = lapply(seq_along(op.dfs), function(i) {
        op.dfs[[i]][,"iter"] = i
        op.dfs[[i]]
      })
      d = setDF(rbindlist(op.dfs, fill = TRUE))
    } else {
      d = getNestedTuneResultsOptPathDf(tune.result)
    }
    num_hypers = length(tune.result$extract[[1]]$x)
    for (hyp in 1:num_hypers) {
      if (!is.numeric(d[, hyp]))
        d[, hyp] = type.convert(as.character(d[, hyp]))
    }
    # rename to be clear this denotes the nested cv
    names(d)[names(d) == "iter"] = "nested_cv_run"

    # items for object
    measures = tune.result$extract[[1]]$opt.path$y.names
    hyperparams = names(tune.result$extract[[1]]$x)
    optimization = getClass1(tune.result$extract[[1]]$control)
    nested = TRUE
  } else {
    if (trafo){
      d = as.data.frame(trafoOptPath(tune.result$opt.path))
    } else {
      d = as.data.frame(tune.result$opt.path)
    }
    # what if we have numerics that were discretized upstream
    num_hypers = length(tune.result$x)
    for (hyp in 1:num_hypers) {
      if (!is.numeric(d[, hyp]))
        d[, hyp] = type.convert(as.character(d[, hyp]))
    }
    measures = tune.result$opt.path$y.names
    hyperparams = names(tune.result$x)
    optimization = getClass1(tune.result$control)
    nested = FALSE
  }

  # off by default unless needed by user
  if (include.diagnostics == FALSE)
    d = within(d, rm("eol", "error.message"))

  # users might not know what dob means, so let's call it iteration
  names(d)[names(d) == "dob"] = "iteration"

  makeS3Obj("HyperParsEffectData", data = d, measures = measures,
    hyperparams = hyperparams,
    diagnostics = include.diagnostics,
    optimization = optimization,
    nested = nested)
}

#' @export
print.HyperParsEffectData = function(x, ...) {
  catf("HyperParsEffectData:")
  catf("Hyperparameters: %s", collapse(x$hyperparams))
  catf("Measures: %s", collapse(x$measures))
  catf("Optimizer: %s", collapse(x$optimization))
  catf("Nested CV Used: %s", collapse(x$nested))
  catf("Snapshot of $data:")
  print(head(x$data))
}

#' @title Plot the hyperparameter effects data
#'
#' @description
#' Plot hyperparameter validation path. Automated plotting method for
#' \code{HyperParsEffectData} object. Useful for determining the importance
#' or effect of a particular hyperparameter on some performance measure and/or
#' optimizer.
#'
#' @param hyperpars.effect.data [\code{HyperParsEffectData}]\cr
#'  Result of \code{\link{generateHyperParsEffectData}}
#' @param x [\code{character(1)}]\cr
#'  Specify what should be plotted on the x axis. Must be a column from
#'  \code{HyperParsEffectData$data}
#' @param y [\code{character(1)}]\cr
#'  Specify what should be plotted on the y axis. Must be a column from
#'  \code{HyperParsEffectData$data}
#' @param z [\code{character(1)}]\cr
#'  Specify what should be used as the extra axis for a particular geom. This
#'  could be for the fill on a heatmap or color aesthetic for a line. Must be a
#'  column from \code{HyperParsEffectData$data}. Default is \code{NULL}.
#' @param plot.type [\code{character(1)}]\cr
#'  Specify the type of plot: \dQuote{scatter} for a scatterplot, \dQuote{heatmap} for a
#'  heatmap, \dQuote{line} for a scatterplot with a connecting line, or \dQuote{contour} for a
#'  contour plot layered ontop of a heatmap.
#'  Default is \dQuote{scatter}.
#' @param loess.smooth [\code{logical(1)}]\cr
#'  If \code{TRUE}, will add loess smoothing line to plots where possible. Note that
#'  this is probably only useful when \code{plot.type} is set to either
#'  \dQuote{scatter} or \dQuote{line}. Must be a column from \code{HyperParsEffectData$data}
#'  Default is \code{FALSE}.
#' @param facet [\code{character(1)}]\cr
#'  Specify what should be used as the facet axis for a particular geom. When
#'  using nested cross validation, set this to \dQuote{nested_cv_run} to obtain a facet
#'  for each outer loop. Must be a column from \code{HyperParsEffectData$data}
#'  Default is \code{NULL}.
#' @template arg_prettynames
#' @param global.only [\code{logical(1)}]\cr
#'  If \code{TRUE}, will only plot the current global optima when setting
#'  x = "iteration" and y as a performance measure from
#'  \code{HyperParsEffectData$measures}. Set this to FALSE to always plot the
#'  performance of every iteration, even if it is not an improvement.
#'  Default is \code{TRUE}.
#' @param interpolate [\code{\link{Learner}} | \code{character(1)}]\cr
#'  If not \code{NULL}, will interpolate non-complete grids in order to visualize a more
#'  complete path. Only meaningful when attempting to plot a heatmap or contour.
#'  This will fill in \dQuote{empty} cells in the heatmap or contour plot. Note that
#'  cases of irregular hyperparameter paths, you will most likely need to use
#'  this to have a meaningful visualization. Accepts either a \link{Learner}
#'  object or the learner as a string for interpolation.
#'  Default is \code{NULL}.
#' @param show.experiments [\code{logical(1)}]\cr
#'  If \code{TRUE}, will overlay the plot with points indicating where an experiment
#'  ran. This is only useful when creating a heatmap or contour plot with
#'  interpolation so that you can see which points were actually on the
#'  original path. Note: if any learner crashes occurred within the path, this
#'  will become \code{TRUE}.
#'  Default is \code{FALSE}.
#' @param show.interpolated [\code{logical(1)}]\cr
#'  If \code{TRUE}, will overlay the plot with points indicating where interpolation
#'  ran. This is only useful when creating a heatmap or contour plot with
#'  interpolation so that you can see which points were interpolated.
#'  Default is \code{FALSE}.
#' @param nested.agg [\code{function}]\cr
#'  The function used to aggregate nested cross validation runs when plotting 2
#'  hyperpars simultaneously. This is only useful when nested cross validation
#'  is used along with plotting a 2 hyperpars.
#'  Default is \code{mean}.
#' @template ret_gg2
#'
#' @note Any NAs incurred from learning algorithm crashes will be indicated in
#' the plot and the NA values will be replaced with the column min/max depending
#' on the optimal values for the respective measure. Execution time will be
#' replaced with the max. Interpolation by its nature will result in predicted
#' values for the performance measure. Use interpolation with caution.
#'
#' @export
#'
#' @examples
#' # see generateHyperParsEffectData
plotHyperParsEffect = function(hyperpars.effect.data, x = NULL, y = NULL,
                               z = NULL, plot.type = "scatter",
                               loess.smooth = FALSE, facet = NULL,
                               pretty.names = TRUE, global.only = TRUE,
                               interpolate = NULL, show.experiments = FALSE,
                               show.interpolated = FALSE, nested.agg = mean) {
  assertClass(hyperpars.effect.data, classes = "HyperParsEffectData")
  assertChoice(x, choices = names(hyperpars.effect.data$data))
  assertChoice(y, choices = names(hyperpars.effect.data$data))
  assertSubset(z, choices = names(hyperpars.effect.data$data))
  assertChoice(plot.type, choices = c("scatter", "line", "heatmap", "contour"))
  assertFlag(loess.smooth)
  assertSubset(facet, choices = names(hyperpars.effect.data$data))
  assertFlag(pretty.names)
  assertFlag(global.only)
  assert(checkClass(interpolate, "Learner"), checkString(interpolate),
         checkNull(interpolate))
  # assign learner for interpolation
  if (checkClass(interpolate, "Learner") == TRUE ||
      checkString(interpolate) == TRUE) {
    lrn = checkLearnerRegr(interpolate)
  }
  assertFlag(show.experiments)
  assertFunction(nested.agg)

  if (length(x) > 1 || length(y) > 1 || length(z) > 1 || length(facet) > 1)
    stopf("Greater than 1 length x, y, z or facet not yet supported")

  d = hyperpars.effect.data$data
  if (hyperpars.effect.data$nested)
    d$nested_cv_run = as.factor(d$nested_cv_run)

  # set flags for building plots
  na.flag = any(is.na(d[, hyperpars.effect.data$measures]))
  z.flag = !is.null(z)
  facet.flag = !is.null(facet)
  heatcontour.flag = plot.type %in% c("heatmap", "contour")

  # deal with NAs where optimizer failed
  if (na.flag){
    d$learner_status = ifelse(is.na(d[, "exec.time"]), "Failure", "Success")
    for (col in hyperpars.effect.data$measures) {
      col_name = stri_split_fixed(col, ".test.mean", omit_empty = TRUE)[[1]]
      if (heatcontour.flag){
        d[,col][is.na(d[,col])] = get(col_name)$worst
      } else {
        if (get(col_name)$minimize){
          d[,col][is.na(d[,col])] = max(d[,col], na.rm = TRUE)
        } else {
          d[,col][is.na(d[,col])] = min(d[,col], na.rm = TRUE)
        }
      }
    }
    d$exec.time[is.na(d$exec.time)] = max(d$exec.time, na.rm = TRUE)
  } else {
    # in case the user wants to show this despite no learner crashes
    d$learner_status = "Success"
  }

  # assign for global only
  if (global.only && x == "iteration" && y %in% hyperpars.effect.data$measures){
    for (col in hyperpars.effect.data$measures) {
      col_name = stri_split_fixed(col, ".test.mean", omit_empty = TRUE)[[1]]
      if (get(col_name)$minimize){
        d[,col] = cummin(d[,col])
      } else {
        d[,col] = cummax(d[,col])
      }
    }
  }

  if ((!is.null(interpolate)) && z.flag && (heatcontour.flag)){
    # create grid
    xo = seq(min(d[,x]), max(d[,x]), length.out = 100)
    yo = seq(min(d[,y]), max(d[,y]), length.out = 100)
    grid = expand.grid(xo, yo, KEEP.OUT.ATTRS = F)
    names(grid) = c(x, y)

    if (hyperpars.effect.data$nested){
      d_new = d
      new_d = data.frame()
      # for loop for each nested cv run
      for (run in unique(d$nested_cv_run)){
        d_run = d_new[d_new$nested_cv_run == run, ]
        regr.task = makeRegrTask(id = "interp", data = d_run[,c(x,y,z)],
          target = z)
        mod = train(lrn, regr.task)
        prediction = predict(mod, newdata = grid)
        grid[, z] = prediction$data[, prediction$predict.type]
        grid$learner_status = "Interpolated Point"
        grid$iteration = NA
        # combine the experiment data with interpolated data
        combined = rbind(d_run[,c(x,y,z,"learner_status", "iteration")], grid)
        # combine each loop
        new_d = rbind(new_d, combined)
      }
      grid = new_d
    } else {
      regr.task = makeRegrTask(id = "interp", data = d[,c(x,y,z)], target = z)
      mod = train(lrn, regr.task)
      prediction = predict(mod, newdata = grid)
      grid[, z] = prediction$data[, prediction$predict.type]
      grid$learner_status = "Interpolated Point"
      grid$iteration = NA
      # combine the experiment data with interpolated data
      combined = rbind(d[,c(x,y,z,"learner_status", "iteration")], grid)
      grid = combined
    }
    # remove any values that would extrapolate the z
    grid[grid[,z] < min(d[,z]), z] = min(d[,z])
    grid[grid[,z] > max(d[,z]), z] = max(d[,z])
    d = grid
  }

  if (hyperpars.effect.data$nested && z.flag){
    averaging = d[, !(names(d) %in% c("iteration", "nested_cv_run",
      hyperpars.effect.data$hyperparams, "eol",
      "error.message", "learner_status")),
      drop = FALSE]
    # keep experiments if we need it
    if (na.flag || (!is.null(interpolate)) || show.experiments){
      hyperpars = lapply(d[, c(hyperpars.effect.data$hyperparams,
        "learner_status")], "[")
    } else {
      hyperpars = lapply(d[, hyperpars.effect.data$hyperparams], "[")
    }
    d = aggregate(averaging, hyperpars, nested.agg)
    d$iteration = 1:nrow(d)
  }

  # just x, y
  if ((length(x) == 1) && (length(y) == 1) && !(z.flag)){
    if (hyperpars.effect.data$nested){
      plt = ggplot(d, aes_string(x = x, y = y, color = "nested_cv_run"))
    } else {
      plt = ggplot(d, aes_string(x = x, y = y))
    }
    if (na.flag){
      plt = plt + geom_point(aes_string(shape = "learner_status",
        color = "learner_status")) +
        scale_shape_manual(values = c("Failure" = 24, "Success" = 0)) +
        scale_color_manual(values = c("red", "black"))
    } else {
      plt = plt + geom_point()
    }
    if (plot.type == "line")
      plt = plt + geom_line()
    if (loess.smooth)
      plt = plt + geom_smooth()
    if (facet.flag)
      plt = plt + facet_wrap(facet)
  } else if ((length(x) == 1) && (length(y) == 1) && (z.flag)){
    # the data we use depends on if interpolation
    if (heatcontour.flag){
      if (!is.null(interpolate)){
        plt = ggplot(data = d[d$learner_status == "Interpolated Point", ],
          aes_string(x = x, y = y, fill = z, z = z)) + geom_raster()
        if (show.interpolated && !(na.flag || show.experiments)){
          plt = plt + geom_point(aes_string(shape = "learner_status")) +
            scale_shape_manual(values = c("Interpolated Point" = 6))
        }
      } else {
        plt = ggplot(data = d, aes_string(x = x, y = y, fill = z, z = z)) +
          geom_tile()
      }
      if ((na.flag || show.experiments) && !(show.interpolated)){
        plt = plt + geom_point(data = d[d$learner_status %in% c("Success",
          "Failure"), ],
          aes_string(shape = "learner_status"),
          fill = "red") +
          scale_shape_manual(values = c("Failure" = 24, "Success" = 0))
      } else if ((na.flag || show.experiments) && (show.interpolated)) {
        plt = plt + geom_point(data = d, aes_string(shape = "learner_status"),
          fill = "red") +
          scale_shape_manual(values = c("Failure" = 24, "Success" = 0,
            "Interpolated Point" = 6))
      }
      if (plot.type == "contour")
        plt = plt + geom_contour()
    } else {
      plt = ggplot(d, aes_string(x = x, y = y, color = z))
      if (na.flag){
        plt = plt + geom_point(aes_string(shape = "learner_status",
          color = "learner_status")) +
          scale_shape_manual(values = c("Failure" = 24, "Success" = 0)) +
          scale_color_manual(values = c("red", "black"))
      } else{
        plt = plt + geom_point()
      }
      if (plot.type == "line")
        plt = plt + geom_line()
    }
  }

  # pretty name changing
  if (pretty.names) {
    if (x %in% hyperpars.effect.data$measures)
      plt = plt +
        xlab(eval(as.name(stri_split_fixed(x, ".test.mean")[[1]][1]))$name)
    if (y %in% hyperpars.effect.data$measures)
      plt = plt +
        ylab(eval(as.name(stri_split_fixed(y, ".test.mean")[[1]][1]))$name)
    if (!is.null(z))
      if (z %in% hyperpars.effect.data$measures)
        plt = plt +
          labs(fill = eval(as.name(stri_split_fixed(z,
            ".test.mean")[[1]][1]))$name)
  }
  return(plt)
}
