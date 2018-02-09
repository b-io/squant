package utils

import java.time.{Clock, Instant, LocalDateTime, ZonedDateTime, ZoneId}
import java.time.format.{DateTimeFormatter, DateTimeFormatterBuilder}
import java.time.temporal.ChronoField

object Dates {
	type Date = LocalDateTime
	type DateFormatter = DateTimeFormatter

	private val zoneId = ZoneId.systemDefault
	private val clock = Clock.system(zoneId)

	def convert(milliseconds: Long): Date = Instant.ofEpochMilli(milliseconds).atZone(zoneId).toLocalDateTime

	def formatter(format: String, zone: String): DateFormatter = new DateTimeFormatterBuilder()
			.appendPattern(format)
			.parseDefaulting(ChronoField.HOUR_OF_DAY, 0)
			.parseDefaulting(ChronoField.MINUTE_OF_HOUR, 0)
			.parseDefaulting(ChronoField.SECOND_OF_MINUTE, 0)
			.toFormatter()
			.withZone(ZoneId.of(zone))

	def now(): Date = LocalDateTime.now(clock)

	def parse(date: String, formatter: DateFormatter): Date = ZonedDateTime.parse(date, formatter)
			.withZoneSameInstant(zoneId)
			.toLocalDateTime
}
