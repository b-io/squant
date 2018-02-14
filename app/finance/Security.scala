package finance

import akka.NotUsed
import akka.stream.ThrottleMode
import akka.stream.scaladsl.Source
import controllers.api.SecurityQuoteAPI
import play.api.Logger
import play.api.libs.json.JsObject
import utils.{Conf, Dates}
import utils.Common._
import utils.Conf.Graph
import utils.Conf.Finance.API
import utils.Dates.Date

import scala.collection.mutable
import scala.concurrent.ExecutionContext.Implicits.global
import scala.concurrent.duration._
import scala.util.{Failure, Random, Success}
import scala.util.control.Exception.allCatch

////////////////////////////////////////////////////////////////////////////////
// SECURITY (ID AND QUOTE GENERATOR)
////////////////////////////////////////////////////////////////////////////////

/**
  * A security contains a source of quotes.
  */
class Security(val id: SecurityId) {
	private val quoteGenerator: SecurityQuoteGenerator = new RealQuoteGenerator(id)

	private val source: Source[SecurityQuote, NotUsed] = {
		Source.unfold(quoteGenerator.seed) { (last: SecurityQuote) =>
			val next = quoteGenerator.nextQuote(last)
			Some(next, next)
		}
	}

	/**
	  * Provides a source that returns the security history.
	  */
	def history(n: Int): Source[SecurityHistory, NotUsed] = {
		source.grouped(n)
				.map(quote => SecurityHistory(
					id,
					quote.map(_.date),
					quote.map(_.values.head),
					quote.map(_.values(1)),
					quote.map(_.values(2)),
					quote.map(_.values(3)),
					quote.map(_.values(4))
				))
				.take(1)
	}

	/**
	  * Provides a source that returns a security update at regular intervals.
	  */
	def update: Source[SecurityUpdate, NotUsed] = {
		source.throttle(elements = 1, per = 100.millis, maximumBurst = 1, ThrottleMode.shaping)
				.map(quote => SecurityUpdate(
					id,
					quote.date,
					quote.values.head,
					quote.values(1),
					quote.values(2),
					quote.values(3),
					quote.values(4)
				))
	}

	override val toString: String = s"Security($id)"
}

////////////////////////////////////////////////////////////////////////////////
// QUOTE GENERATOR
////////////////////////////////////////////////////////////////////////////////

trait SecurityQuoteGenerator {
	def seed: SecurityQuote

	def nextQuote(lastQuote: SecurityQuote): SecurityQuote
}

class FakeQuoteGenerator(id: SecurityId) extends SecurityQuoteGenerator {
	private val logger = Logger(getClass)

	private def random: Double = Random.nextDouble

	def seed: SecurityQuote = {
		logger.info(s"[$id] Get the seed")
		SecurityQuote(id, Dates.now(), List(SecurityValue(random * 100), SecurityValue(100)))
	}

	def nextQuote(lastQuote: SecurityQuote): SecurityQuote = SecurityQuote(
		id,
		Dates.now(),
		List(SecurityValue(lastQuote.values.head.raw * (0.95 + (0.1 * random))), SecurityValue(100))
	)
}

class RealQuoteGenerator(id: SecurityId) extends SecurityQuoteGenerator {
	private val logger = Logger(getClass)

	private val api: SecurityQuoteAPI = Conf.INJECTOR.instanceOf(classOf[SecurityQuoteAPI])
	private val beat = SecurityId("")
	private val cache: mutable.Queue[(Date, Seq[SecurityValue])] = mutable.Queue.empty[(Date, Seq[SecurityValue])]
	private var lastCacheRefresh = Dates.convert(0L)

	// Fetch the quotes and update the cache
	private def updateCache(): Unit = lastCacheRefresh.synchronized {
		// Return if the cache is fresh
		if (!Dates.convert(System.currentTimeMillis - API.REFRESH_TIME).isAfter(lastCacheRefresh))
			return
		lastCacheRefresh = Dates.now()

		// Fetch the quotes
		api.getQuotesJson(id.toString).onComplete {

			// Check the response
			case Success(quotes) =>
				val error = quotes.fields.filter(f => API.ERROR.equals(f._1))
				if (error.isEmpty) {
					if (quotes.keys.contains(API.DATA)) {
						quotes(API.DATA) match {

							// Parse the JSON object
							case o: JsObject => cache.synchronized {
								// Get the cache date
								val fromDate = if (cache.nonEmpty) cache.last._1 else API.FROM_DATE
								logger.info(s"[$id] Update the cache of quotes from [$fromDate]")

								// Check the fields
								val allFields = o.fields.map(f => (
										allCatch opt Dates.parse(f._1.toString, API.DATE_FORMATTER),
										allCatch opt (f._2 \ API.OPEN).as[String].toDouble,
										allCatch opt (f._2 \ API.HIGH).as[String].toDouble,
										allCatch opt (f._2 \ API.LOW).as[String].toDouble,
										allCatch opt (f._2 \ API.CLOSE).as[String].toDouble,
										allCatch opt (f._2 \ API.VOLUME).as[String].toDouble
								))

								// Filter the fields
								val fields = allFields.filter(f => f._1.isDefined && f._2.isDefined)
										.map(f => (
												f._1.get,
												f._2.getOrElse[Double](0),
												f._3.getOrElse[Double](0),
												f._4.getOrElse[Double](0),
												f._5.getOrElse[Double](0),
												f._6.getOrElse[Double](0)
										))
								val n = allFields.size - fields.size
								if (n > 0)
									logger.error(s"[$id] Filter $n invalid quotes")

								// Update the cache
								fields.filter(_._1.isAfter(fromDate))
										.sortBy(_._1)
										.takeRight(Graph.SIZE)
										.foreach(
											f => {
												logger.debug(s"[$id] + Add [$f]")
												cache.enqueue((
														f._1,
														List(SecurityValue(f._2),
															SecurityValue(f._3),
															SecurityValue(f._4),
															SecurityValue(f._5),
															SecurityValue(f._6))
												))
												if (cache.lengthCompare(Graph.SIZE) > 0) cache.dequeue
											}
										)
							}
							case _ => logger.error(
								s"[$id] Could not fetch the quotes: Invalid JSON format"
							)
						}
					} else logger.error(s"[$id] Could not fetch the quotes: No [${API.DATA}]")
				} else logger.error(s"[$id] Could not fetch the quotes: ${error.head._2}")
			case Failure(e) => logger.error(s"[$id] Could not fetch the quotes: ${e.getMessage}")
		}
	}

	def seed: SecurityQuote = {
		updateCache()
		logger.info(s"[$id] -> Seed")
		SecurityQuote(beat, API.FROM_DATE, List(SecurityValue(0), SecurityValue(0)))
	}

	def nextQuote(lastQuote: SecurityQuote): SecurityQuote = {
		updateCache()
		// Return the next quote (i.e. the one just after the last quote)
		if (cache.exists(_._1.isAfter(lastQuote.date))) {
			val data = cache.filter(_._1.isAfter(lastQuote.date)).front
			val quote = SecurityQuote(id, data._1, data._2)
			logger.debug(s"[$id] -> Next quote: [$quote] (previously [$lastQuote])")
			quote
		} else SecurityQuote(beat, lastQuote.date, lastQuote.values)
	}
}

////////////////////////////////////////////////////////////////////////////////
// JSON SERIALIZER
////////////////////////////////////////////////////////////////////////////////

case class SecurityQuote(id: SecurityId, date: Date, values: Seq[SecurityValue])

/** Value class for the ID of a security */
class SecurityId private(val raw: String) extends AnyVal {
	override def toString: String = raw
}

object SecurityId {

	import play.api.libs.json._ // Combinator syntax

	def apply(raw: String) = new SecurityId(raw)

	implicit val securityIdReads: Reads[SecurityId] = JsPath.read[String].map(SecurityId(_))

	implicit val securityIdWrites: Writes[SecurityId] = (id: SecurityId) => JsString(id.raw)
}

/** Value class for the quote value of a security (open / high / low / close value or volume) */
class SecurityValue private(val raw: Double) extends AnyVal {
	override def toString: String = String.valueOf(raw)
}

object SecurityValue {

	import play.api.libs.json._ // Combinator syntax

	def apply(value: Double): SecurityValue = new SecurityValue(value)

	implicit val securityValueWrites: Writes[SecurityValue] = (value: SecurityValue) => JsNumber(value.raw)
}

/**
  * JSON presentation class for security history (used for automatic JSON conversion).
  *
  * @see https://www.playframework.com/documentation/2.6.x/ScalaJson
  */
case class SecurityHistory(id: SecurityId,
                           dates: Seq[Date],
                           opens: Seq[SecurityValue],
                           highs: Seq[SecurityValue],
                           lows: Seq[SecurityValue],
                           closes: Seq[SecurityValue],
                           volumes: Seq[SecurityValue])
object SecurityHistory {

	import play.api.libs.json._ // Combinator syntax

	implicit val securityHistoryWrites: Writes[SecurityHistory] = (history: SecurityHistory) =>
		Json.obj(
			"type" -> "security-history",
			"id" -> history.id,
			"dates" -> history.dates,
			"opens" -> history.opens,
			"highs" -> history.highs,
			"lows" -> history.lows,
			"closes" -> history.closes,
			"volumes" -> history.volumes
		)
}

/**
  * JSON presentation class for security update (used for automatic JSON conversion).
  *
  * @see https://www.playframework.com/documentation/2.6.x/ScalaJson
  */
case class SecurityUpdate(id: SecurityId,
                          date: Date,
                          open: SecurityValue,
                          high: SecurityValue,
                          low: SecurityValue,
                          close: SecurityValue,
                          volume: SecurityValue)
object SecurityUpdate {

	import play.api.libs.json._ // Combinator syntax

	implicit val securityUpdateWrites: Writes[SecurityUpdate] = (update: SecurityUpdate) =>
		Json.obj(
			"type" -> "security-update",
			"id" -> update.id,
			"date" -> update.date,
			"open" -> update.open,
			"high" -> update.high,
			"low" -> update.low,
			"close" -> update.close,
			"volume" -> update.volume
		)
}
