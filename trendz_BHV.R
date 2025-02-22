###..............................................................................
##
##   Shiny App
##
##   App to display the time series of a variable from a distinct dataset and station
##   for a selection of years, respectively a selection of months in each year
##   and check for trends / long term development
##
##   comment in the check block in the server user interface block (ui <- ....)
##   to activate the check function
###..............................................................................
##   Check application to check all available years
##   ==> check whether there are anomalous years if compared to the other years
##   Check button saves information on controller and date of the check
##
##   written by:  stephan.lange@awi.de
##                christian.lehr@awi.de
##   last modified: 2021-03-23
##
##   last check: 2020-01-27
##   checked by: christian.lehr@awi.de
##
###..............................................................................
##
## open issues:
##
##
##
###..............................................................................
##
## last modification:
## 2021-06-09 SL: add options to choose statistics, plot on new right axis
## 2021-03-23 SL: change pathes to git structure
## 2020-06-24 CL: mean value of selection of data added as horizontal line to the boxplots panel
##
###..............................................................................
##
## comments:
##
###..............................................................................

library(shiny)
library(data.table)
library(nlme)
library(Kendall)


  yearlyDatasetPaths <- read.csv("/isipd/projects/sparc/LTO/R_database/Time_series_preprocessing/required-scripts-and-files/settings_shiny/yearlyDataPath_BHV_noflag.csv", stringsAsFactors = FALSE,
                                 strip.white = TRUE)
  allowedVariables <- read.csv("/isipd/projects/sparc/LTO/R_database/Time_series_preprocessing/required-scripts-and-files/settings_shiny/allowedVariables.csv", stringsAsFactors = FALSE,
                               strip.white = TRUE)
  filterbasepath     <- "/isipd/projects/sparc/LTO/R_database/Time_series_preprocessing/required-scripts-and-files/settings/filter.files/"
  checkbasepath      <- "/isipd/projects/sparc/LTO/R_database/Time_series_preprocessing/required-scripts-and-files/settings/check.files/"
  # read file for modification of style of shiny-app
  source("/isipd/projects/sparc/LTO/R_database/Time_series_preprocessing/required-scripts-and-files/additionals_shiny/appCSS.R")


##
addDateDetails <- function(d) {
  # Derives date details from POSIXct times
  d$day   <- as.POSIXlt(d$UTC)$mday
  d$yday  <- as.POSIXlt(d$UTC)$yday + 1
  d$month <- as.POSIXlt(d$UTC)$mon + 1
  d$year  <- as.POSIXlt(d$UTC)$year + 1900
  d$week  <- round(d$day/7)
  d$datum <- as.Date(d$UTC)
  return(d)
}

###..............................................................................
#### server logic ----
server <- shinyServer(function(input, output, session) {
  # holds data
  store <- reactiveValues(data = data.frame())
  
  # define check files and paths analogue to filter files and paths
  # use the same directory for saving of check files
  getCheckpath <- function() {
    stationprefix <- switch(input$station,
                            "Bayelva" = "Ba",
                            #"Kurungnakh" = "Ku",
                            "Samoylov" = "Sa",
                            "Sardakh" = "Sd",
                            "TVC" = "TVC")
    return(paste0(checkbasepath, stationprefix, "_check_complete.dat"))
  }
  
  getChecklist <- function() {
    checkpath <- getCheckpath()
    if (file.exists(checkpath))
      return(read.table(checkpath, stringsAsFactors = FALSE, strip.white = TRUE,
                        sep = ",", dec = ".", header = T))
    else return(NULL)
  }
  
  ### for manual check: ----
  # checkpath <- paste0(checkbasepath, "Ba_check_complete.dat")
  # check.list <- read.table(checkpath, stringsAsFactors = FALSE, strip.white = TRUE, sep = ",", dec = ".", header = T)
  #input <- data.frame(station = character(0),dataset = character(0),variable = character(0), begin = character(0), end = character(0), check3 = character(0), controller3 = character(0))
  #input <- data.frame(station = "Bayelva",dataset = "BaMet1998",variable = "Tair_200", begin = 1998, end = 2001, check3 = NA, controller3 = NA)
  
  #input$dataset <- "BaMet1998"
  # input$variable <- "Tair_200"
  
  # get check variables
  observeEvent(list(input$year, input$variable, input$dataset, input$station), {
    check.list <- getChecklist()
    validate(
      need(nrow(check.list[(check.list$dataset == input$dataset) & (check.list$variable == input$variable), ]) > 0, 'This combination of dataset and variable is not available')
    )
    outz <<- check.list[(check.list$dataset == input$dataset) & (check.list$variable == input$variable), ]
    # if (nrow(check.list[(check.list$dataset == input$dataset) & (check.list$variable == input$variable), ]) > 0) {
    #   outz <<- check.list[(check.list$dataset == input$dataset) & (check.list$variable == input$variable), ]}
    # validate(
    #    need(outz, 'Problem with outz')
    # )
    output$check3 <- renderText({
      paste(outz$controller3, outz$check3)
    })
  })
  ####  trendplot -------
  output$trendplot <- renderPlot({
    variablename <- input$variable
    
    # validation
    validate(need(variablename != "", "Please select a variable"))
    validate(need(nrow(store$data) > 0, "No data available."))
    validate(need(!all(is.na(store$data[, list(variablename)])), "All data is NA."))
    
    # subset to selected years and months
    if (input$custommonths != "") {
      # handle custom months string
      tryCatch({
        allowedmonths <- numeric(0)
        # iterate over custom months string
        #browser()
        for (months in trimws(unlist(strsplit(input$custommonths, ",")))) {
          # test if string is a range of months
          months <- trimws(unlist(strsplit(months, "-")))
          months <- as.numeric(months)
          if (length(months) == 2) {
            allowedmonths <- append(allowedmonths, seq(months[1], months[2]))
          } else {
            allowedmonths <- append(allowedmonths, months)
          }
        }
        allowedmonths <- as.numeric(allowedmonths)
        if (any(is.na(allowedmonths))) stop()
      }, error = function(e) {
        validate(need(FALSE, paste0("Could not parse months. Please enter single months ",
                                    "or ranges of months (3-5) separated by commas, i.e. ",
                                    "'9-12, 1-3, 4'\n")))
      })
    } else {
      allowedmonths <- do.call(seq, as.list(input$monthslider))
    }
    
    # subset data for statistics
    if (input$stats.p != "") {
      # handle custom months string
      tryCatch({
        allowed.p <- as.numeric(input$stats.p)
        if (any(is.na(allowed.p))) stop()
      }, error = function(e) {
        validate(need(FALSE, paste0("Could not parse percentage. Please enter single number ",
                                    "between 0-100  ",)))
      })
    } else {
      allowed.p <- 80
    }
    
    
    plotdata <- store$data[store$data$year >= input$yearslider[1] &
                             store$data$year <= input$yearslider[2] &
                             store$data$month %in% allowedmonths]
    
    # set plot margins
    par(mar = c(4, 3, 1, 3))
    
    nyears <- length(unique(plotdata$year))
    n.colours <- rainbow(nyears)
    n.colours <-rev(c("#04e762","#f5b700","#00a1e4","#dc0073","#89fc00",
                      "#ffb2e6","#d972ff","#8447ff","#8cffda",
                      "#f2efea","#fc7753","#66d7d1","#403d58","#dbd56e",
                      "#7c6a0a","#babd8d","#ffdac6","#fa9500","#eb6424"))[1:nyears]
    
    plotdata$colour <- n.colours[factor(plotdata$year)]
    uhhi <- aggregate(plotdata[, get(variablename)] ~ plotdata$year, data = plotdata, FUN = input$stats.f)
    uhhi2 <- aggregate(plotdata[, get(variablename)] ~ plotdata$year, data = plotdata, FUN = "length")
    uhhi<-uhhi[which(max(uhhi2[,2]) * allowed.p * 0.01 <= uhhi2[,2]),] 
    
    
    colnames(uhhi) <- c("year",variablename)
    colnames(uhhi) <- c("year","parameter")
    #browser()
    
    # plot
    plot(plotdata$UTC, plotdata[, get(variablename)], pch = ".", col = plotdata$colour,
         xlab = "", ylab = "", xaxt = "n")
    # draw x-axis
    xTickis <- axis.POSIXct(1, at = seq(min(plotdata$UTC), max(plotdata$UTC), by = "year"))
    # draw x-axis grid aligning with date ticks
    abline(v = seq(min(plotdata$UTC), max(plotdata$UTC), by = "year"),
           col = "gray", lty = "dotted")
    abline(v = xTickis, col = "lightgray", lty = "dotted")
    # draw y-axis grid
    grid(nx = NA, ny = NULL)
    
    if(length(uhhi[,1])>2){
      
      model2 <- gls(parameter ~ year, correlation = corAR1(form = ~1), method = 'ML', data = uhhi)
      predict(model2,data.frame(year=c(uhhi[1,1], uhhi[1,length(uhhi[,1])])))
    }else{
      model2<-paste0("Not enought timeseries data, please choose another variable or reduce the data per year percentage")
    }
    uhhi$yearposix <- (uhhi$year - 1970) * 31557600
   
    #browser()
    
    if(input$stats.f=="sum"){
      par(new=TRUE)
      
      plot(((uhhi[, 1] - 1970) * 31557600) + 15768000, uhhi[, 2], cex = 4, pch = "-", xlab = "", ylab = "", xaxt = "n", yaxt = "n")
      text(((uhhi[, 1] - 1970) * 31557600) + 15768000, uhhi[, 2], labels = round(uhhi[, 2], 2),pos = 1, cex = 1.5, col="darkblue")
      axis(4,col.ticks = "darkblue",col="darkblue",col.axis="darkblue")
    }else{
      points(((uhhi[, 1] - 1970) * 31557600) + 15768000, uhhi[, 2],  cex = 4, pch = "-")
      text(((uhhi[, 1] - 1970) * 31557600) + 15768000, uhhi[, 2], labels = round(uhhi[, 2], 2),pos = 1, cex = 1.5,  col="darkblue")
      axis(4,col.ticks = "darkblue",col="darkblue",col.axis="darkblue")
    }
    
    if(length(uhhi[,1])>2){
      lines(c((1980-1970) * 31557600, (2030-1970) * 31557600),
            c(predict(model2, data.frame(year = c(1980,2030)))), 
            col = "green4", lwd = 2, lty = 2)
    }
    legend("topright", bg = "transparent", text.col = "darkblue", text.font = 2, cex = 2, box.col = "transparent",
           legend = input$stats.f)
    
    if(length(uhhi[,1])>2){
      legend("bottomright", bg = "transparent", text.col = "green4", text.font = 3, cex = 2, box.col = "transparent",
             legend = paste(" slope:                   ",format(coef(model2)[2], digits = 3),"\np-value (MannKendall):",
                            format((MannKendall(uhhi[,2])$sl), digits = 3)))    
    }
    
    output$statistics <- renderText({
      if(length(uhhi[,1])>2){
        paste("Summary:\n",
              paste(capture.output(summary(plotdata[, 2])), collapse = "\n"),
              "\n\nModel:",
              paste(capture.output(summary(model2)), collapse = "\n"),
              collapse = "\n")
      }else{
        paste("Summary:\n",
              paste(capture.output(summary(plotdata[, 2])), collapse = "\n"),
              "\n\nModel:",
              paste(model2, collapse = "\n"),
              collapse = "\n")
      }
    })
  })
  
  output$yearplot <- renderPlot({
    variablename <- input$variable
    
    # validation
    validate(need(variablename != "", "Please select a variable"))
    validate(need(nrow(store$data) > 0, "No data available."))
    validate(need(!all(is.na(store$data[, list(variablename)])), "All data is NA."))
    
    # subset to selected years and months
    if (input$custommonths != "") {
      # handle custom months string
      tryCatch({
        allowedmonths <- numeric(0)
        # iterate over custom months string
        #browser()
        for (months in trimws(unlist(strsplit(input$custommonths, ",")))) {
          # test if string is a range of months
          months <- trimws(unlist(strsplit(months, "-")))
          months <- as.numeric(months)
          if (length(months) == 2) {
            allowedmonths <- append(allowedmonths, seq(months[1], months[2]))
          } else {
            allowedmonths <- append(allowedmonths, months)
          }
        }
        allowedmonths <- as.numeric(allowedmonths)
        if (any(is.na(allowedmonths))) stop()
      }, error = function(e) {
        validate(need(FALSE, paste0("Could not parse months. Please enter single months ",
                                    "or ranges of months (3-5) separated by commas, i.e. ",
                                    "'9-12, 1-3, 4'\n")))
      })
    } else {
      allowedmonths <- do.call(seq, as.list(input$monthslider))
    }
    
    plotdata <- store$data[store$data$year >= input$yearslider[1] &
                             store$data$year <= input$yearslider[2] &
                             store$data$month %in% allowedmonths]
    
    # calculate monthly means
    monthlymeans <- plotdata[, .(value = mean(get(variablename), na.rm = TRUE),
                                 percentNA = sum(is.na(get(variablename)) /
                                                   length(get(variablename))),
                                 sd = sd(get(variablename), na.rm = TRUE)),
                             by = .(month, year)]
    
    dailymeans <- plotdata[, .(value = mean(get(variablename), na.rm = TRUE),
                               percentNA = sum(is.na(get(variablename)) /
                                                 length(get(variablename))),
                               sd = sd(get(variablename), na.rm = TRUE)),
                           by = .(yday, month, year)]
    
    # set plot margins
    par(mar = c(4, 3, 1, 1))
    
    nyears <- length(unique(monthlymeans$year))
    n.colours <- rainbow(nyears)
    n.colours <-rev(c("#04e762","#f5b700","#00a1e4","#dc0073","#89fc00",
                      "#ffb2e6","#d972ff","#8447ff","#8cffda",
                      "#f2efea","#fc7753","#66d7d1","#403d58","#dbd56e",
                      "#7c6a0a","#babd8d","#ffdac6","#fa9500","#eb6424"))[1:nyears]
    ridgeSpacing <- 3
    ridgeOffset <- 2
    dailymeans$scaledvalue <- scale(dailymeans$value, center = FALSE)
    plot(dailymeans$yday, NULL, xlim = -30 + 30 * c(min(monthlymeans$month), max(monthlymeans$month) + 1),
         ylim = c(0, nyears * ridgeSpacing + ridgeOffset/2),
         xlab = "", ylab = "", xaxt = "n", yaxt = "n", type = "n")
    for (i in 1:nyears) {
      year <- unique(monthlymeans$year)[i]
      for (month in unique(monthlymeans$month)) {
        lines(dailymeans$yday[dailymeans$year == year & dailymeans$month == month],
              dailymeans$scaledvalue[dailymeans$year == year & dailymeans$month == month] + ridgeOffset + (i - 1) * ridgeSpacing,
              col = n.colours[i], lwd = 2)
      }
      # y-axis label
      mtext(year, side = 2, at = ridgeOffset + (i - 1) * ridgeSpacing, col = n.colours[i], cex = 1.3)
      # draw y-axis grid
      abline(h = ridgeOffset + (i - 1) * ridgeSpacing, col = "lightgray", lty = "dotted")
    }
    # draw x axis and save ticks
    xTicks <- axis(1, at = -15 + 30.5 * seq(min(monthlymeans$month), max(monthlymeans$month)),
                   labels = seq(min(monthlymeans$month), max(monthlymeans$month)))
    # xTicks2 <- axis(1, at = -30 + 30.5 * seq(min(monthlymeans$month), max(monthlymeans$month)),
    #        labels = seq(min(monthlymeans$month), max(monthlymeans$month)))
    # draw x-axis grid aligning with date ticks
    abline(v = -30 + 30.5 * seq(min(monthlymeans$month), max(monthlymeans$month)), col = "lightgray", lty = "dotted")
    
    ## plot
    #plot(dailymeans$yday, dailymeans$value, cex = .3, col = "gray",
    #   xlab = "", ylab = "", xaxt = "n")
    ## draw x-axis
    ## draw monthly means per year
    #xvals <- split(monthlymeans$month * 30 - 15, monthlymeans$year)
    #yvals <- split(monthlymeans$value, monthlymeans$year)
    #for (i in 1:length(xvals)) {
    #  lines(xvals[[i]], yvals[[i]], col = n.colours[i], type = "b")
    #}
    ##mapply(lines, xvals, yvals, col = n.colours, type = "b")
  })
  
  output$boxplots <- renderPlot({
    variablename <- input$variable
    
    # validation
    validate(need(variablename != "", "Please select a variable"))
    validate(need(nrow(store$data) > 0, "No data available."))
    validate(need(!all(is.na(store$data[, list(variablename)])), "All data is NA."))
    
    # subset to selected years and months
    if (input$custommonths != "") {
      # handle custom months string
      tryCatch({
        allowedmonths <- numeric(0)
        # iterate over custom months string
        #browser()
        for (months in trimws(unlist(strsplit(input$custommonths, ",")))) {
          # test if string is a range of months
          months <- trimws(unlist(strsplit(months, "-")))
          months <- as.numeric(months)
          if (length(months) == 2) {
            allowedmonths <- append(allowedmonths, seq(months[1], months[2]))
          } else {
            allowedmonths <- append(allowedmonths, months)
          }
        }
        allowedmonths <- as.numeric(allowedmonths)
        if (any(is.na(allowedmonths))) stop()
      }, error = function(e) {
        validate(need(FALSE, paste0("Could not parse months. Please enter single months ",
                                    "or ranges of months (3-5) separated by commas, i.e. ",
                                    "'9-12, 1-3, 4'\n")))
      })
    } else {
      allowedmonths <- do.call(seq, as.list(input$monthslider))
    }
    
    plotdata <- store$data[store$data$year >= input$yearslider[1] &
                             store$data$year <= input$yearslider[2] &
                             store$data$month %in% allowedmonths]
    
    # set plot margins
    par(mar = c(4, 3, 1, 1))
    
    nyears <- length(unique(plotdata$year))
    n.colours <- rainbow(nyears)
    n.colours <-rev(c("#04e762","#f5b700","#00a1e4","#dc0073","#89fc00",
                      "#ffb2e6","#d972ff","#8447ff","#8cffda",
                      "#f2efea","#fc7753","#66d7d1","#403d58","#dbd56e",
                      "#7c6a0a","#babd8d","#ffdac6","#fa9500","#eb6424"))[1:nyears]
    plotdata$colour <- n.colours[factor(plotdata$year)]
    uhhi <- aggregate(plotdata[, get(variablename)] ~ plotdata$year, data = plotdata, FUN = mean)
    
    #browser()
    
    # plot
    boxplot(plotdata[, get(variablename)] ~ plotdata$year, col = n.colours, ylab = "", xlab = "")
    # draw y-axis grid
    grid(nx = NA, ny = NULL)
    # mean value of selection of data
    abline(h = mean(plotdata[, get(variablename)], na.rm = TRUE), lwd = 2)
    legend("topleft", legend = "mean", lwd = 2)
    # plot boxplots on top
    boxplot(plotdata[, get(variablename)] ~ plotdata$year, col = n.colours, ylab = "", xlab = "", add = TRUE)
  })
  
  observeEvent(list(input$dataset, input$station), {
    # update dataset list
    datasets <- yearlyDatasetPaths$dataset[yearlyDatasetPaths$station == input$station]
    if (input$dataset %in% datasets) {
      # double update to trigger input$dataset invalidation
      updateSelectInput(session, "dataset", choices = datasets, selected = input$dataset)
    } else {
      updateSelectInput(session, "dataset", choices = datasets)
      return()
    }
    
    # update variable list
    varlist <- allowedVariables$variable[allowedVariables$dataset == input$dataset]
    ## If variable was selected, update filter list, read data and draw overview plot, else abort
    if (input$variable %in% varlist) {
      # double update to trigger input$variable invalidation
      updateSelectInput(session, "variable", choices = varlist, selected = input$variable)
    } else {
      updateSelectInput(session, "variable", choices = varlist)
      return()
    }
  })
  
  observeEvent(input$variable, ignoreInit = TRUE, {
    ## Get data
    paths <- yearlyDatasetPaths$path[yearlyDatasetPaths$dataset == input$dataset]
    # path will be empty if dataset changed and input$variable did not update
    if (length(paths) == 0) {
      browser()
      return()
    }
    
    timing <- proc.time()
    
    # read data and save in global variable
    temp <- data.frame()
    for (path in paths) {
      temp <- rbind(temp, fread(path, sep = ',', header = TRUE, stringsAsFactors = FALSE,
                                select = c("UTC", input$variable)))
    }
    temp$UTC <- as.POSIXct(temp$UTC, tz = 'UTC')
    # add date information
    temp <- addDateDetails(temp)
    # overwrite store
    store$data <- temp
    
    cat(file = stderr(), "\nTime spent reading data:",
        (proc.time() - timing)[3], "s\n")
  })
  
  observeEvent(input$buttonSaveCheck, ignoreInit = TRUE, {
    #### write check to file ###
    # withBusyIndicatorServer("buttonSaveCheck", {
    # check for name
    if (input$controller == "") {
      stop("Please enter your name to confirm the check.")
    }
    
    # ## read old check list
    checklist <- getChecklist()
    # # check if checklist exists and if not, create one!
    if (is.null(checklist)) {
      warning("No checklist exists for that year! Creating one...")
      checklist <- data.frame(station = character(0), dataset = character(0), variable = character(0), begin = character(0), end = character(0), check3 = character(0), controller3 = character(0))
    }
    
    # construct check line and new checklist
    # index of combination of dataset and variable to be checked
    ind.check <- which((input$dataset == checklist$dataset) & (input$variable == checklist$variable))
    
    #####..............................................................................

    ## allow to check independent whether the data set was already checked
    ## ==> always save the newest check
    checklist$check3[ind.check] <- as.character(Sys.time()) # (Sys.Date())
    checklist$controller3[ind.check] <- input$controller
    # save the begin and start of the checked period.
    # Always check the complete monitoring period from the very beginning till the last complete year before the date of the check.
    checklist$begin[ind.check] <- min(yearlyDatasetPaths$year)
    checklist$end[ind.check] <- max(yearlyDatasetPaths$year) - 1
    # other variant:
    # save only the years which are selected with the slider: min: input$yearslider[1]; max: input$yearslider[2]
    checklistNew <- checklist
    ####
    
    # validate check line by comparing names and dimensions
    if (any(names(checklist) != names(checklistNew)) |
        #  ncol(checklist) != length(checkline)     |
        ncol(checklist) != ncol(checklistNew)    #|
        # nrow(checklist) != nrow(checklistNew) - 1
    ) {
      stop("BUG: Output check structure not valid, aborting.")
    }
    # write new check list to file
    checkpath <- getCheckpath()
    write.table(checklistNew, file = checkpath, row.names = FALSE, sep = ",", dec = ".")
    
    check.list <- getChecklist()
    
    # check whether combination of dataset and variable is available
    validate(
      need(nrow(check.list[(check.list$dataset == input$dataset) & (check.list$variable == input$variable), ]) > 0, 'This combination of dataset and variable is not available')
    )
    outz <<- check.list[(check.list$dataset == input$dataset) & (check.list$variable == input$variable), ]
    output$check3  <- renderText({
      paste(outz$controller3, outz$check3)
    })
    #browser()
  })
  #  })
})

### user interface ------
ui <- shinyUI(fluidPage(
  tags$style(appCSS),
  tags$style("#statistics {font-size:12px;}"),
  p(" "),
  fluidRow(
    column(3, wellPanel(
      # useShinyjs(),
      selectInput("station", "Choose a station:", selected = "Bayelva",
                  choices = sort(unique(yearlyDatasetPaths$station))),
      selectInput("dataset", "Choose a dataset:", selected = "BaMet2009",
                  choices = yearlyDatasetPaths$dataset[yearlyDatasetPaths$station == "Bayelva"]),
      selectInput("variable", "Choose a variable:",  choices = NULL),
      # yearslider for year selection
      sliderInput("yearslider", "Choose years:", step = 1, ticks = FALSE, sep = "",
                  min = min(yearlyDatasetPaths$year), max = max(yearlyDatasetPaths$year),
                  value = range(yearlyDatasetPaths$year)),
      # monthslider for year selection
      sliderInput("monthslider", "Choose months:",
                  min = 1, max = 12, ticks = FALSE,
                  value = c(1, 12), step = 1),
      textInput("custommonths", NULL,
                placeholder = "custom months, i.e. '9-12, 1-3, 4'"),
      
      ####..................................................................................
      #### check block ----------------
      #### uncomment the next lines to activate the check function
      ####
      # textInput("controller", "Your name:", placeholder = "Please enter your Initials to confirm the check."),
      # actionButton("buttonSaveCheck", "Check consistency of complete series",
      #        style = 'white-space:normal;color:black;background-color:violet'),
      # verbatimTextOutput("check3"),
      ####..................................................................................
      
      selectInput("stats.f", "Choose a statistic:", selected = "mean",
                  choices = c("mean","median","min","max","sum")),
      textInput("stats.p",  "Data per year",
                placeholder = "default is 80 %"),
      p("Statistics"),
      verbatimTextOutput("statistics")
      
    )),
    column(9,
           plotOutput("trendplot", height = 300),
           plotOutput("yearplot", height = 800),
           plotOutput("boxplots", height = 300)
    )
  )
))

#### run --------
# options(shiny.reactlog = FALSE)
shinyApp(ui = ui, server = server)
#runApp(shinyApp(ui = ui, server = server))
