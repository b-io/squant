################################################################################
# GLOBAL VARIABLES
################################################################################

# COMMON #######################################################################

DEBUG = false

# The container ID
CONTAINER_ID = "securities"

# The cursor location
LOCATION = undefined # pageX and pageY

# CHARTS #######################################################################

# All chart IDs
IDS = []

# The chart ID of reference
REFERENCE_ID = undefined

# All plots per chart ID
PLOTS = {}

# The interval of time between the points
POINTS_INTERVAL = 60000 # 300000 [ms] (5 minutes)

# The number of points to be averaged
SAMPLE_SIZE = 1 # the sample rate is then 12 * 5 [min] = 1 [h]

# The interval of time between the updates
UPDATE_INTERVAL = 0 # [ms]

# The candlesticks flag (experimental)
CANDLESTICKS = true

# All color palettes
PALETTES =
	classic: ["#333333", "#00CC00", "#0000CC", "#CC00CC", "#00CCCC", "#CC6600", "#CCCC00", "#CC0000"]
	classicLight: ["#333333", "#29CC29", "#2929CC", "#CC7A29", "#29CCCC", "#CCCC29", "#CC29CC", "#CC2929"]
	classicRainbow: ["#000000", "#33FF33", "#3333FF", "#FF9933", "#33FFFF", "#FFFF33", "#FF33FF"]
	original: ["#333333", "#CC8800", "#00CC88", "#8800CC", "#0044CC", "#44CC00", "#CC0044"]

# The current palette
PALETTE = PALETTES.classic

# All colors
COLORS =
	white: "#FFF"
	veryLightGrey: "#E0E0E0"
	lightGrey: "#BFBFBF"
	grey: "#808080"
	darkGrey: "#404040"
	black: "#000"

	red: PALETTE[PALETTE.length - 1]
	green: PALETTE[1]
	blue: PALETTE[2]


################################################################################
# MAIN
################################################################################

$ ->
	# WEBSOCKET ################################################################

	# Open a WebSocket to the server
	ws = new WebSocket $("body").data("ws-url")

	# Process the server message
	ws.onmessage = (event) ->
		event.preventDefault()
		message = JSON.parse event.data
		switch message.type
			when "security-history"
				populateSecurityHistory(message)
			when "security-update"
				updateSecurityChart(message)
			else
				info(message.id, message)

	# Send a request to the server to watch the specified security
	$("#add-security-form").submit((event) ->
		event.preventDefault()
		# Send the request
		ws.send(JSON.stringify(id: $("#add-security-text").val()))
		# Reset the form
		$("#add-security-text").val("")
	)

	# EVENTS ###################################################################

	# Bind the keyboard controller
	getContainer().hover((-> @focus()), (-> @blur()))
		.keydown((event) ->
			for id in IDS
				plot = PLOTS[id]
				if plot.show
					# Clear the zoom and the selection
					clearXAxis(plot)
					showChart(id, plot)
					plot.clearSelection()
		)

	# Bind the mouse controller
	getContainer().mousemove((event) ->
		event.preventDefault()
		LOCATION = event
	)

	# Bind the touch controller
	document.getElementById(CONTAINER_ID).addEventListener("touchmove", (event) ->
		event.preventDefault()

		x = 0
		y = 0
		i = 0
		while i < event.targetTouches.length
			x += event.targetTouches[i].pageX
			y += event.targetTouches[i].pageY
			++i
		x /= i
		y /= i
		LOCATION =
			pageX: x
			pageY: y
	, false)

	# CHARTS ###################################################################

	# Update the charts (infinite loop)
	updateCharts()


################################################################################
# CONTROLLERS
################################################################################

# Create the chart and populate the last quotes for the specified security
populateSecurityHistory = (message) ->
	# Get the security ID (chart ID)
	id = message.id
	if not id?
		return

	info(id, "Populate the history")

	# Create and init the chart
	series = createSeries(id, message)
	plot = createChart(id, series)
	initChart(id, plot)

	# Show the chart if there is data or hide otherwise
	if exist(message.closes, (p) -> p > 0)
		showChart(id, plot)
	else
		hideChart(id, plot)

# Update the chart with the specified quote for the specified security
updateSecurityChart = (message) ->
	# Get the chart ID and the corresponding plot
	id = message.id
	plot = PLOTS[id]
	if not id? or not plot?
		return

	# Return if there is no new point
	points = getPoints(plot.getData(), 0)
	if points[points.length - 1][0] >= createDate(message.date)
		return

	debug(id, "Update the chart")

	# Update the series
	updateSeries(id, plot, message)

	# Shift the x-axis
	clearXAxis(plot)

	# Shift the y-axes
	i = 0
	while i < plot.getOptions().yaxes.length
		clearYAxis(plot, i)
		++i

	# Show the chart if there is data or hide otherwise
	if message.close > 0
		showChart(id, plot)
	else
		hideChart(id, plot)

# Flip the chart and fetch the sentiments of the last tweets about the specified security
handleFlip = (id) ->
	container = getChartContainer(id)
	detailsHolder = container.find(".details-holder")
	detailsHolder.empty()

	if container.hasClass("flipped")
		# Unflip the chart
		detailsHolder.hide()
		container.removeClass("flipped")
		showTooltips(id, PLOTS[id])
	else
		# Flip the chart
		hideTooltips(id, PLOTS[id])
		container.addClass("flipped")
		detailsHolder.show()

		# Display loading information
		detailsHolder.append($("<h4>")
			.text("Determining whether you should buy or sell based on the sentiment of recent tweets..."))
		detailsHolder.append($("<div>")
			.addClass("progress progress-striped active")
			.append($("<div>")
				.addClass("progress-bar")
				.css
					width: "100%"
			)
		)

		# Fetch the sentiments of the last tweets
		$.ajax
			url: "/sentiment/" + container.prop("id")
			dataType: "json"
			context: container

			# Show the result
			success: (data) ->
				detailsHolder = $(this).find(".details-holder")
				detailsHolder.empty()
				switch data.label
					when "pos"
						detailsHolder.append($("<h4>").text("The tweets say BUY!"))
						detailsHolder.append($("<img>").prop("src", "/assets/images/buy.png"))
					when "neg"
						detailsHolder.append($("<h4>").text("The tweets say SELL!"))
						detailsHolder.append($("<img>").prop("src", "/assets/images/sell.png"))
					else
						detailsHolder.append($("<h4>").text("The tweets say HOLD!"))
						detailsHolder.append($("<img>").prop("src", "/assets/images/hold.png"))

			# Show the error
			error: (jqXHR, textStatus, error) ->
				detailsHolder = $(this).find(".details-holder")
				detailsHolder.empty()
				error = jqXHR.responseText
				try
					error = JSON.parse(error)["error"]
				detailsHolder.append($("<h2>").text(error))


################################################################################
# CREATE CHARTS
################################################################################

createSeries = (id, message) ->
	series = []

	# Set the x-values
	xValues = createDates(message.dates)

	if CANDLESTICKS
		# Add the values
		values = zip(xValues, message.opens, message.closes, message.lows, message.highs)
		data = $.plot.candlestick.createCandlestick(
			label: "Values"
			data: values
			yaxis: 1
			candlestick:
				show: true
				lineWidth: "5px"
		)
		series.push(data[0]) # values
		series.push(data[1]) # max
		series.push(data[2]) # min
	else
		# Add the close values
		values = zip(xValues, message.closes)
		series.push(
			label: "Values"
			data: values
			yaxis: 1
			lines:
				show: true
		)

		# Add the volumes
		series.push(
			label: "Volumes"
			data: zip(xValues, message.volumes)
			yaxis: 2
			bars:
				show: true
			threshold:
				below: 0
				color: COLORS.red
		)

		###
		# Add delta (first derivative)
		delta = derivative(quotes).map((p) -> [p[0], POINTS_INTERVAL * p[1]])
		series.push(
			label: "Delta"
			data: sample(delta, SAMPLE_SIZE)
			yaxis: 2
			bars:
				show: true
			threshold:
				below: 0
				color: COLORS.red
		)

		# Add gamma (second derivative)
		gamma = smooth(derivative(delta).map((p) -> [p[0], POINTS_INTERVAL * p[1]]), SAMPLE_SIZE)
		series.push(
			label: "Gamma"
			data: gamma
			yaxis: 2
			lines:
				show: true
			threshold:
				below: 0
				color: COLORS.red
		)
	    ###

	return series

# Update the series
updateSeries = (id, plot, message) ->
	# Get the close values and the volumes
	series = plot.getData()
	closes = getPoints(series, 0)
	volumes = getPoints(series, 1)

	# Get the new values
	newDate = createDate(message.date)
	newClose = message.close
	newVolume = message.volume

	# Update the series
	if newClose > 0 and exist(closes, (q) -> q[1] <= 0)
		# Replace all initial dummy quotes with the new one
		closes = closes.map(-> [newDate, newClose])
		volumes = volumes.map(-> [newDate, newVolume])
	else
		# Add the new close value
		closes.shift()
		closes.push([newDate, newClose])
		# Add the new volume
		volumes.shift()
		volumes.push([newDate, newVolume])
	series[0].data = closes
	series[1].data = volumes

	# Update the plot
	plot.setData(series)

# Create the chart for the specified security and series
createChart = (id, series) ->
	info(id, "Create the chart")

	# Create the element containing the chart
	legend = $("<div>")
		.prop("id", "legend-" + id)
		.addClass("legend")
	if CANDLESTICKS
		legend.hide()
	chart = $("<div>")
		.prop("id", "chart-" + id)
		.addClass("chart")
	chartHolder = $("<div>")
		.addClass("chart-holder")
		.append(legend)
		.append(chart)

	# Create the element containing the details (hidden by default)
	detailsHolder = $("<div>")
		.addClass("details-holder")
		.hide()

	# Create the flipper
	flipper = $("<div>")
		.prop("id", id)
		.addClass("flipper")
		.append(chartHolder)
		.append(detailsHolder)
	container = $("<div>")
		.prop("id", "flip-container-" + id)
		.addClass("flip-container")
		.append(flipper)
		.dblclick((event) -> handleFlip(id))

	# Add the components to the body
	getContainer().prepend(container)

	# Bind the touch controller
	container = document.getElementById("flip-container-" + id)
	# - Handle double touch
	touchTimer = undefined
	container.addEventListener("touchstart", (event) ->
		if not touchTimer?
			touchTimer = setTimeout((-> touchTimer = null), 500)
		else
			event.preventDefault()

			clearTimeout touchTimer
			touchTimer = null
			handleFlip(id)
	, false)
	# - Handle touch move
	container.addEventListener("touchmove", (event) ->
		event.preventDefault()

		REFERENCE_ID = id
	, false)

	# Create the plot
	plot = chart.plot(series, getChartOptions(id, series)).data("plot")
	IDS.push(id)
	PLOTS[id] = plot

	return plot

getChartOptions = (id, series) ->
	bars:
		show: false
		align: "center"
		barWidth: SAMPLE_SIZE * POINTS_INTERVAL
		fill: true
		lineWidth: 1
		order: 2
	colors: PALETTE
	crosses:
		show: true
		mode: "xy"
		colors:
			x: COLORS.darkGrey
			y: PALETTE
		lineWidth: 1
		opacity: 1.0
	grid:
		show: true
		aboveData: false
		autoHighlight: false
		borderWidth: 2
		clickable: false
		editable: true
		hoverable: true # must be true to enable "plothover"
		markings: setVerticalStripes
	legend:
		show: true
		showValues: false
		container: getLegend(id)
		noColumns: 0
		position: "ne"
		labelBoxBorderColor: COLORS.white
	lines:
		show: false
		fill: false
		fillColor:
			colors: series.map(-> opacity: 0.5)
	points:
		show: false
		fill: true
		fillColor: PALETTE
	selection:
		mode: "x"
	series:
		candlestick:
			active: CANDLESTICKS
		shadowSize: 1
	tooltips:
		show: true
	xaxis:
		show: true
		mode: "time"
		autoscaleMargin: 0.05
		min: getSeriesXMin(series)
		max: getSeriesXMax(series)
		color: COLORS.black
		tickColor: "rgba(0, 0, 0, 0.33)"
		tickFormatter: (val, axis) ->
			moment(val).format("DD.MM HH:mm")
		tickLength: 6
		timeformat: "%d.%m %H:%M"
		timezone: "browser"
	yaxis:
		show: true
		autoscaleMargin: 0.05
		color: COLORS.black
		tickColor: "rgba(0, 0, 0, 0.33)"
		tickFormatter: (value, axis) ->
			formatNumber(value)
		tickLength: 6
	yaxes: [
		position: "left"
		tickLength: "full"
		,
		position: "right"
		tickLength: "full"
	]

setVerticalStripes = (axes) ->
	markings = []

	# Get the first day
	d = createDate(axes.xaxis.min)
	d.setSeconds 0
	d.setMinutes 0
	d.setHours 0

	# Set the vertical stripes
	i = d.getTime()
	step = 24 * 60 * 60 * 1000
	while i <= axes.xaxis.max
		markings.push
			colors: [COLORS.white, COLORS.veryLightGrey]
			xaxis:
				from: i
				to: i + step # i + 2 * 24 * 60 * 60 * 1000
		i += 2 * step # 7 * 24 * 60 * 60 * 1000

	return markings

initChart = (id, plot) ->
	info(id, "Init the chart")

	# Init the cursor location
	if not LOCATION?
		LOCATION =
			pageX: parseToInt(plot.offset().left + plot.width() / 2)
			pageY: parseToInt(plot.offset().top + plot.height() / 2)

	# Bind the controllers
	chart = getChart(id)
	chart.bind("plothover", (event, pos, item) ->
		event.preventDefault()

		if not isFlipped(id)
			REFERENCE_ID = id
			debug(REFERENCE_ID, "New reference")
	)
	chart.bind("plotselected", (event, ranges) ->
		event.preventDefault()

		debug(id, "Zoom")
		for id in IDS
			plot = PLOTS[id]
			if plot.show
				# Zoom and clear the selection
				setXAxis(plot, ranges.xaxis.from, ranges.xaxis.to)
				showChart(id, plot)
				plot.clearSelection()
	)

	# Init the crosses
	initCrosses(id, plot)

	# Init the tooltips
	initTooltips(id, plot)

showChart = (id, plot) ->
	plot.show = true
	getChartContainer(id).fadeIn(600)
	plot.setupGrid()
	plot.draw()

hideChart = (id, plot) ->
	info(id, "Hide the chart")
	plot.show = false
	getChartContainer(id).fadeOut(600)


################################################################################
# UPDATE CHARTS
################################################################################

getColor = (plot, i, yValue) ->
	if yValue?
		threshold = getYThreshold(plot, i)
		if threshold? and yValue < threshold.below
			return threshold.color
	return plot.getOptions().colors[i]

updateCharts = () ->
	if IDS.length > 0
		# Get the reference plot
		if not REFERENCE_ID?
			REFERENCE_ID = IDS[0]
			info(REFERENCE_ID, "New reference")
		plot = PLOTS[REFERENCE_ID]

		# Get the x-value from the cursor location
		reference = plot.c2p(
			left: parseToInt(LOCATION.pageX - plot.offset().left)
			top:  parseToInt(LOCATION.pageY - plot.offset().top)
		)
		xValue = reference.x

		# Limit the range of the x-values
		axes = plot.getAxes()
		if xValue < axes.xaxis.min
			xValue = axes.xaxis.min
		else if xValue > axes.xaxis.max
			xValue = axes.xaxis.max

		# Update all charts
		for id in IDS
			if not isFlipped(id)
				# Get the corresponding plot
				plot = PLOTS[id]

				if plot.show
					# Find all y-values at the x-value
					yValues = findYValues(plot, xValue)

					if yValues.length > 0
						# Show the dynamic components
						plot.update = true
						showLegendValues(id, plot, yValues)
						showCrosses(id, plot, xValue, yValues)
						showTooltips(id, plot, xValue, yValues)
					else
						# Hide the dynamic components
						debug(id, "Hide the components")
						plot.update = false
						hideLegendValues(id, plot)
						hideCrosses(id, plot)
						hideTooltips(id, plot)

	# Loop
	setTimeout((-> updateCharts()), UPDATE_INTERVAL)

# LEGENDS ######################################################################

getLegend = (id) ->
	$("#legend-" + id)

validLegendValues = (plot) ->
	return plot.getOptions().legend.show and plot.getOptions().legend.showValues

showLegendValues = (id, plot, yValues) ->
	if not validLegendValues(plot)
		return

	# Get the legend and the labels
	legend = $("#legend-" + id + " .legendLabel")
	labels = plot.getData().map((s) -> s.label)

	# Add the y-values to the legend
	i = 0
	for yValue in yValues
		legend.eq(i).text labels[i] + ": " + yValue.toFixed(2)
		++i

	legend.show()

hideLegendValues = (id, plot) ->
	if not validLegendValues(plot)
		return

	debug(id, "Hide the y-values from the legend")

	# Get the legend and the labels
	legend = legend = $("#legend-" + id + " .legendLabel")
	labels = plot.getData().map((s) -> s.label)

	# Remove the values from the legend
	i = 0
	for label in labels
		legend.eq(i).text label
		++i

	legend.show()

# CROSSES ######################################################################

validCrosses = (plot) ->
	options = plot.getOptions().crosses
	return plot.getOptions().grid.show and options.show and options.mode?

initCrosses = (id, plot) ->
	if not validCrosses(plot)
		return

	# Init the crosses
	plot.crosses =
		x: -1
		y: []

	# Hook the cross to the draw overlay
	plot.hooks.drawOverlay.push((plot, ctx) -> drawCrosses(id, plot, ctx))

showCrosses = (id, plot, xValue, yValues) ->
	if not plot.update or not validCrosses(plot)
		return

	# Get the options
	options = plot.getOptions().crosses

	# Set the x-coordinate
	if xValue?
		plot.crosses.x = getXOffset(plot, xValue)
	else
		plot.crosses.x = -1

	# Set the y-coordinates
	plot.crosses.y = []
	if yValues? and yValues.length > 0
		i = 0
		while i < plot.getYAxes().length
			yValue = yValues[i]
			options.colors.y[i] = getColor(plot, i, yValue)
			plot.crosses.y.push(getYOffset(plot, i, yValue))
			++i

	# Redraw the overlay
	plot.triggerRedrawOverlay()

hideCrosses = (id, plot) ->
	if not validCrosses(plot)
		return

	debug(id, "Hide the crosses")
	plot.triggerRedrawOverlay()

drawCrosses = (id, plot, ctx) ->
	if not plot.update or not validCrosses(plot) or plot.crosses.x == -1
		return

	# Get the options
	options = plot.getOptions().crosses

	# Init the context
	ctx.save()
	if options.opacity?
		ctx.globalAlpha = options.opacity
	ctx.lineWidth = options.lineWidth
	ctx.lineJoin = "round"

	# Translate to the origin
	o = plot.getPlotOffset()
	ctx.translate o.left, o.top

	# Draw the x-value
	if options.mode.indexOf("x") != -1
		ctx.beginPath()
		ctx.strokeStyle = options.colors.x
		drawX = parseToInt(plot.crosses.x)
		ctx.moveTo drawX, 0
		ctx.lineTo drawX, plot.height()
		ctx.stroke()

	# Draw the y-values
	if options.mode.indexOf("y") != -1
		i = 0
		while i < plot.getYAxes().length
			ctx.beginPath()
			ctx.strokeStyle = options.colors.y[i]
			drawY = parseToInt(plot.crosses.y[i])
			ctx.moveTo 0, drawY
			ctx.lineTo plot.width(), drawY
			ctx.stroke()
			++i

	# Restore the context
	ctx.restore()

###
drawPoint = (id, point, radius, color) ->
	plot = PLOTS[id]

	if plot?
		o = plot.pointOffset(
			x: point[0]
			y: point[1]
		)
		x = o.left
		y = o.top
		canvas = $("#chart-" + id + " .flot-overlay")[0]
		ctx = canvas.getContext("2d")
		ctx.beginPath()
		ctx.strokeStyle = COLORS.white
		ctx.lineWidth = 1
		ctx.arc(x, y, radius, 0, Math.PI * 2, false)
		ctx.closePath()
		ctx.stroke()
		ctx.fillStyle = color
		ctx.fill()
		ctx.beginPath()
		ctx.lineWidth = 1
		ctx.strokeStyle = COLORS.black
		ctx.arc(x, y, radius + 2, 0, Math.PI * 2, false)
		ctx.closePath()
		ctx.stroke()
###

# TOOLTIPS #####################################################################

validTooltips = (plot) ->
	options = plot.getOptions().tooltips
	return plot.getOptions().grid.show and options.show

# Create x- and y-tooltips for the specified security
initTooltips = (id, plot) ->
	if not validTooltips(plot)
		return

	# Create the x-tooltip
	xTooltip = $("<div id='tooltip-" + id + "-x'></div>")
		.addClass("tooltip")
		.addClass("unselected")
		.css
			display: "none"
			"text-align": "center"
	.appendTo("#" + CONTAINER_ID)
	xTooltip.width = getFullWidth(xTooltip)
	xTooltip.height = getFullHeight(xTooltip)

	# Create the y-tooltips
	yTooltips = []
	i = 0
	for yAxis in plot.getYAxes()
		color = getColor(plot, i)
		yTooltip = $("<div id='tooltip-" + id + "-y-" + i + "'></div>")
			.addClass("tooltip")
			.css
				display: "none"
				width: yAxis.box.width
				"text-align": if yAxis.position == "left" then "right" else "left"
				background: color
				background: "-webkit-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
				background: "linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
				background: "-o-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
				background: "-ms-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
				background: "-moz-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
				background: "-webkit-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
		.appendTo("#" + CONTAINER_ID)
		yTooltip.width = getFullWidth(yTooltip)
		yTooltip.height = getFullHeight(yTooltip)
		yTooltips.push(yTooltip)
		++i

	# Store the tooltips in the plot
	plot.tooltips =
		x: xTooltip
		y: yTooltips

showTooltips = (id, plot, xValue, yValues) ->
	if not plot.update or not validTooltips(plot)
		return

	# Show the x-tooltip
	xAxis = plot.getXAxes()[0]
	xTooltip = plot.tooltips.x
	if xValue?
		# Set the lengths
		xTooltip.width = Math.max(xTooltip.width, getFullWidth(xTooltip))
		tickLength = getTickLength(xAxis)

		# Set the left position of the x-tooltip
		offset = plot.offset().left + getXOffset(plot, xValue)
		left = offset - xTooltip.width / 2

		# Set the top position of the x-tooltip
		top = plot.offset().top + plot.height() + tickLength

		# Set up the x-tooltip
		xTooltip.html(moment(xValue).format("DD.MM HH:mm:ss"))
			.css
				left: parseToInt(left)
				top: parseToInt(top)
		if id == REFERENCE_ID
			# Display the color of the first derivative
			if yValues? and yValues.length > 1
				if yValues[1] < 0
					xTooltip.addClass("red-border")
						.removeClass("green-border")
				else
					xTooltip.addClass("green-border")
						.removeClass("red-border")
				xTooltip.removeClass("blue-border")
			# Display the selected color
			else
				xTooltip.addClass("blue-border")
					.removeClass("red-border")
					.removeClass("green-border")
			xTooltip.removeClass("unselected")
		else
			xTooltip.addClass("unselected")
				.removeClass("red-border")
				.removeClass("green-border")
				.removeClass("blue-border")
	xTooltip.fadeIn(600)

	# Show all y-tooltips
	i = 0
	while i < plot.getYAxes().length
		yAxis = plot.getYAxes()[i]
		yTooltip = plot.tooltips.y[i]

		if yValues? and yValues.length > 0
			yValue = yValues[i]

			# Set the lengths
			yTooltip.height = Math.max(yTooltip.height, getFullHeight(yTooltip))
			tickLength = getTickLength(yAxis)

			# Set the left position of the y-tooltip
			offset = plot.offset().left - plot.getPlotOffset().left + yAxis.box.left
			# - For the left y-axes
			if yAxis.position == "left"
				left = offset - tickLength
				# For the left axis without ticks
				if tickLength == 0
					left -= plot.getOptions().grid.borderWidth
				left -= 2 * getMargin(yTooltip)
			# - For the right y-axes
			else
				left = offset + tickLength
				# For the right axis without ticks
				if tickLength == 0
					left += plot.getOptions().grid.borderWidth

			# Set the top position of the y-tooltip
			offset = plot.offset().top + getYOffset(plot, i, yValue)
			top = offset - yTooltip.height / 2

			# Set the color of the y-tooltip
			color = getColor(plot, i, yValue)

			# Set up the y-tooltip
			yTooltip.html(formatNumber(yValue))
				.css
					left: parseToInt(left)
					top: parseToInt(top)
					background: color
					background: "-webkit-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
					background: "linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
					background: "-o-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
					background: "-ms-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
					background: "-moz-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
					background: "-webkit-linear-gradient(rgba(1,1,1,0) 0, " + color + " 10%, " + color + " 90%, rgba(1,1,1,0))"
		yTooltip.fadeIn(600)

		++i

hideTooltips = (id, plot) ->
	if not validTooltips(plot)
		return

	debug(id, "Hide the tooltips")
	plot.tooltips.x.fadeOut(600)
	plot.tooltips.y.map((y) -> y.fadeOut(600))


################################################################################
# UTILS
################################################################################

# COMMON #######################################################################

getContainer = () ->
	return $("#" + CONTAINER_ID)

# CHARTS #######################################################################

getChart = (id) ->
	return $("#chart-" + id)
getChartContainer = (id) ->
	return $("#flip-container-" + id)
isFlipped = (id) ->
	return getChartContainer(id).hasClass("flipped")

# POINTS #######################################################################

getPoints = (series, i) ->
	return series[i].data

getXValues = (points) ->
	p[0] for p in points
getYValues = (points) ->
	p[1] for p in points

getXMin = (points) ->
	return getMin(getXValues(points))
getXMax = (points) ->
	return getMax(getXValues(points))
getYMin = (points) ->
	return getMin(getYValues(points))
getYMax = (points) ->
	return getMax(getYValues(points))

getSeriesXMin = (series) ->
	return getMin(series.map((s) -> getXMin(s.data)))
getSeriesXMax = (series) ->
	return getMax(series.map((s) -> getXMax(s.data)))
getSeriesYMin = (series) ->
	return getMin(series.map((s) -> getYMin(s.data)))
getSeriesYMax = (series) ->
	return getMax(series.map((s) -> getYMax(s.data)))

getXOffset = (plot, value) ->
	o = plot.p2c(x: value)
	return bound(o.left, 0, plot.width())
getYOffset = (plot, i, value) ->
	point = {}
	point["y" + (i + 1)] = value
	o = plot.p2c(point)
	return bound(o.top, 0, plot.height())

# AXES #########################################################################

clearXAxis = (plot) ->
	setXAxis(plot, getSeriesXMin(plot.getData()), getSeriesXMax(plot.getData()))
clearYAxis = (plot, i) ->
	points = getPoints(plot.getData(), i)
	if i == 0
		min = getYMin(points) * 0.9
		max = getYMax(points) * 1.025
	else
		min = getYMin(points) * 0.9
		max = getYMax(points) * 10
	setYAxis(plot, i, min, max)

setXAxis = (plot, min, max) ->
	xAxis = plot.getOptions().xaxes[0] # must be xaxes (and not xaxis)
	xAxis.min = min
	xAxis.max = max
setYAxis = (plot, i, min, max) ->
	yAxis = plot.getOptions().yaxes[i]
	yAxis.min = min
	yAxis.max = max

getYThreshold = (plot, i) ->
	if i < plot.getOptions().yaxes.length
		return plot.getOptions().yaxes[i].threshold
	return undefined

getTickLength = (axis) ->
	if axis? and axis.tickLength? and axis.tickLength > 0
		return axis.tickLength
	return 0

# Find all y-values at the specified x-value in the specified plot
findYValues = (plot, xValue) ->
	yValues = []

	# Limit the x-value
	xAxis = plot.getAxes().xaxis
	if xValue >= xAxis.min and xValue <= xAxis.max

		# Find the y-value for each series
		series = plot.getData()
		i = 0
		while i < series.length
			points = getPoints(series, i)

			# Find the points just after the x-value
			j = 0
			while j < points.length and points[j][0] <= xValue
				++j

			# Find the y-value at the x-value using interpolation
			yValue = interpolate(points[j - 1], points[j], xValue)
			if yValue?
				yValues.push(yValue)

			++i

	return yValues

# OPERATIONS ###################################################################

derivative = (points) ->
	d = []
	if points.length == 1
		d.push[[points[0][0], 0]]
	else
		d.push([points[0][0], slope(points[0], points[1]) / 2])
		i = 1
		lastIndex = points.length - 1
		while i < lastIndex
			d.push([points[i][0], average(slope(points[i - 1], points[i]), slope(points[i], points[i + 1]))])
			++i
		d.push([points[lastIndex][0], slope(points[lastIndex - 1], points[lastIndex]) / 2])
	return d

interpolate = (p1, p2, xValue) ->
	if p1? and not p2?
		return p1[1]
	else if not p1? and p2?
		return p2[1]
	else if p1? and p2?
		return p1[1] + (xValue - p1[0]) * slope(p1, p2)
	return undefined

slope = (p1, p2) ->
	if p2[0] - p1[0] == 0
		return 0
	return (p2[1] - p1[1]) / (p2[0] - p1[0])

sample = (points, interval) ->
	s = []

	semiInterval = round((interval - 1) / 2)
	i = 0
	while i < points.length
		# Compute the local mean
		localMean = 0
		k = 0
		for j in [i - semiInterval .. i + semiInterval]
			if j >= 0 and j < points.length
				localMean += points[j][1]
				++k

		# Add the point
		s.push([points[i][0], localMean / k])

		i += interval

	return s

smooth = (points, interval) ->
	s = []

	semiInterval = round((interval - 1) / 2)
	i = 0
	while i < points.length
		# Compute the local mean
		localMean = 0
		k = 0
		for j in [i - semiInterval .. i + semiInterval]
			if j >= 0 and j < points.length
				localMean += points[j][1]
				++k

		# Add the point
		s.push([points[i][0], localMean / k])

		++i

	return s


################################################################################
# COMMON
################################################################################

# ARRAYS #######################################################################

exist = (array, condition) ->
	for e in array
		if condition(e)
			return true
	return false

getMin = (array) ->
	return Math.min.apply(Math, array)
getMax = (array) ->
	return Math.max.apply(Math, array)

getMean = (array) ->
	return sum(array) / array.length

sum = (array) ->
	return array.reduce(x, y) -> x + y

zip = () ->
	lengths = (a.length for a in arguments)
	limit = Math.min(lengths...)
	for i in [0...limit]
		a[i] for a in arguments

# COMPONENTS ###################################################################

getCss = (component, property) ->
	return parseToInt(component.css(property).trim().split(" ")[0].replace("px", ""))

getWidth = (component) ->
	return getCss(component, "width")
getHeight = (component) ->
	return getCss(component, "height")

getBorder = (component) ->
	return getCss(component, "border")
getMargin = (component) ->
	return getCss(component, "margin")

getFullWidth = (component) ->
	return getWidth(component) + getBorder(component) + getMargin(component)
getFullHeight = (component) ->
	return getHeight(component) + getBorder(component) + getMargin(component)

# DATES ########################################################################

createDate = (time) ->
	return new Date(time)
createDates = (times) ->
	createDate(d) for d in times

# LOGS #########################################################################

debug = (id, message) ->
	if DEBUG
		console.debug("[DEB][" + id + "] " + message)

info = (id, message) ->
	console.info("[INF][" + id + "] " + message)

error = (id, message) ->
	console.error("[ERR][" + id + "] " + message)

# NUMBERS ######################################################################

average = (a, b) ->
	return (a + b) / 2

bound = (value, from, to) ->
	return Math.max(from, Math.min(value, to))

formatNumber = (number) ->
	return number.toPrecision(5)

parseToInt = (number) ->
	return round(number)

round = (number) ->
	return Math.round(number)
