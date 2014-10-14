# This file is a part of the fmi package (http://github.com/rOpenGov/fmi)
# in association with the rOpenGov project (ropengov.github.io)

# Copyright (C) 2014 Jussi Jousimo. 
# All rights reserved.

# This program is open source software; you can redistribute it and/or modify 
# it under the terms of the FreeBSD License (keep this notice): 
# http://en.wikipedia.org/wiki/BSD_licenses

# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

#' A class to make requests to the FMI open data API.
#'
#' @import R6
#' @import raster
#' @references See citation("fmi")
#' @author Jussi Jousimo \email{jvj@@iki.fi}
#' @exportClass FMIWFSClient
#' @export FMIWFSClient
FMIWFSClient <- R6::R6Class(
  "FMIWFSClient",
  inherit = rwfs::WFSFileClient,
  private = list(
    transformTimeValuePairData = function(response, timeColumnNamePrefix="time", measurementColumnNamePrefix="result_MeasurementTimeseries_point_MeasurementTVP_value", variableColumnNames) {
      if (missing(response))
        stop("Required argument 'response' missing.")
      if (missing(variableColumnNames))
        stop("Required argument 'variableColumnNames' missing.")
      
      data <- response@data      
      measurementColumnIndex <- substr(names(data), 1, nchar(measurementColumnNamePrefix)) == measurementColumnNamePrefix
      names(data)[measurementColumnIndex] <- sapply(1:sum(measurementColumnIndex), function(x) paste0("measurement", x))
      data$variable=rep(variableColumnNames, nrow(response) / length(variableColumnNames))
      response@data <- data
      
      return(response)
    },
    
    getRasterLayerNames = function(startDateTime, endDateTime, by, variables) {
      dateSeq <- seq.Date(as.Date(startDateTime), as.Date(endDateTime), by=by)
      x <- expand.grid(date=dateSeq, measurement=variables)
      layerNames <- do.call(function(date, measurement) paste(measurement, date, sep="."), x)
      return(layerNames)
    },
    
    processParameters = function(startDateTime=NULL, endDateTime=NULL, 
                                 bbox=NULL, fmisid=NULL) {
      if (inherits(startDateTime, "POSIXt")) {
        startDateTime <- asISO8601(startDateTime)
      }
      if (inherits(endDateTime, "POSIXt")) {
        endDateTime <- asISO8601(endDateTime)
      }
      if (!is.null(fmisid)) {
        if (valid_fmisid(fmisid)) {
          fmisid <- fmisid
        }
      }
      if (inherits(bbox, "Extent")) { 
        bbox <- with(attributes(bbox), paste(xmin, xmax, ymin, ymax, sep=","))
      }
      return(list(startDateTime=startDateTime, endDateTime=endDateTime, 
                  fmisid=fmisid, bbox=bbox))
    }
  ),
  public = list(
    getFinlandBBox = function() {
      return(raster::extent(c(19.0900,59.3000,31.5900,70.130)))
    },
    
    getRasterURL = function(request, parameters) {
      layers <- self$listLayers(request=request)
      if (length(layers) == 0) return(character(0))
      
      meta <- self$getLayer(request=request, layer=layers[1], parameters=parameters)
      if (is.character(meta)) return(character(0))
      
      return(meta@data$fileReference)
    },
    
    getDailyWeather = function(request, startDateTime, endDateTime, bbox=NULL,
                               fmisid=NULL) {
      if (!missing(request)) {        
        # FMISID takes precedence over bbox (usually more precise)
        if (!is.null(bbox) & !is.null(fmisid)) {
          bbox <- NULL
          warning("Both bbox and fmisid provided, using only fmisid.")
        }
        
        p <- private$processParameters(startDateTime=startDateTime, 
                                       endDateTime=endDateTime, bbox=bbox, 
                                      fmisid=fmisid)
        
        if (!is.null(fmisid)) {
          request$setParameters(request="getFeature",
                                storedquery_id="fmi::observations::weather::daily::timevaluepair",
                                starttime=p$startDateTime,
                                endtime=p$endDateTime,
                                fmisid=p$fmisid,
                                parameters="rrday,snow,tday,tmin,tmax")
        } else if (!is.null(bbox)) {
          request$setParameters(request="getFeature",
                                storedquery_id="fmi::observations::weather::daily::timevaluepair",
                                starttime=p$startDateTime,
                                endtime=p$endDateTime,
                                bbox=p$bbox,
                                parameters="rrday,snow,tday,tmin,tmax")
        } else {
          stop("Either fmisid or bbox must be provided!")
        }
      }
      response <- self$getLayer(request=request, layer="PointTimeSeriesObservation", 
                                crs="+proj=longlat +datum=WGS84", swapAxisOrder=TRUE, 
                                parameters=list(splitListFields=TRUE))
      if (is.character(response)) return(character())
      
      response <- private$transformTimeValuePairData(response=response, 
                                                     variableColumnNames=c("rrday","snow","tday","tmin","tmax"))
      # TODO: set name1 ... name3 column names
      
      return(response)
    },
    
    getMonthlyWeatherGrid = function(request, startDateTime, endDateTime) {
      if (!missing(request)) {
        p <- private$processParameters(startDateTime=startDateTime, endDateTime=endDateTime)
        request$setParameters(request="getFeature",
                              storedquery_id="fmi::observations::weather::monthly::grid",
                              starttime=p$startDateTime,
                              endtime=p$endDateTime)
      }
      response <- self$getRaster(request=request, parameters=list(splitListFields=TRUE))
      if (is.character(response)) return(character())
      
      names(response) <- private$getRasterLayerNames(startDateTime=startDateTime,
                                                     endDateTime=endDateTime,
                                                     by="month",
                                                     variables=c("MonthlyMeanTemperature", "MonthlyPrecipitation"))
      return(response)
    }
  )
)