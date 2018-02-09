package controllers.api

import javax.inject.{Inject, Singleton}

import play.api.{Configuration, Logger}
import play.api.libs.json.{JsObject, Json, JsString, JsValue, Reads}
import play.api.libs.ws.{WSClient, WSResponse}
import play.api.mvc.{AbstractController, Action, AnyContent, ControllerComponents, Result}
import utils.Conf.Sentiment.API

import scala.concurrent.{ExecutionContext, Future}

@Singleton
class SecuritySentimentAPI @Inject()(ws: WSClient, config: Configuration, cc: ControllerComponents)
		(implicit ec: ExecutionContext) extends AbstractController(cc) {
	private val logger = Logger(getClass)

	private val sentimentAPI = config.get[String]("sentiment.api.url")
	private val tweetAPI = config.get[String]("tweet.api.url")

	private implicit val tweetReads: Reads[Tweet] = Json.reads[Tweet]

	case class Tweet(text: String)

	def get(id: String): Action[AnyContent] = Action.async {
		logger.info(s"[$id] Get the security sentiment")

		val futureSecuritySentiments: Future[Result] = for {
			tweets <- getTweets(id) // get tweets that contain the security id
			futureSentiments = loadSentimentFromTweets(tweets.json) // queue web requests each tweets' sentiments
			sentiments <- Future.sequence(futureSentiments) // when the sentiment responses arrive, set them
		} yield Ok(parseToJson(sentiments))

		futureSecuritySentiments.recover {
			case _: NoSuchElementException => InternalServerError(
				Json.obj("error" -> JsString(s"[$id] Could not fetch the tweets"))
			)
		}
	}

	private def getTextSentiment(text: String): Future[WSResponse] = {
		logger.info(s"Get the text sentiment of [$text] from [${ API.URL }]")

		ws.url(sentimentAPI).post(Map("text" -> Seq(text)))
	}

	private def getAverageSentiment(responses: Seq[WSResponse], label: String): Double = {
		responses.map {
			response => (response.json \\ label).head.as[Double]
		}.sum / responses.size.max(1) // avoid division by zero
	}

	private def loadSentimentFromTweets(json: JsValue): Seq[Future[WSResponse]] = {
		(json \ "statuses").as[Seq[Tweet]] map (tweet => getTextSentiment(tweet.text))
	}

	private def getTweets(id: String): Future[WSResponse] = {
		val url = tweetAPI.format(id)
		logger.info(s"[$id] Get the latest tweets from [$url]")

		ws.url(url).get.withFilter { response => response.status == OK }
	}

	private def parseToJson(sentiments: Seq[WSResponse]): JsObject = {
		logger.info(s"Parse the sentiments to JSON: [$sentiments]")

		val neg = getAverageSentiment(sentiments, "neg")
		val neutral = getAverageSentiment(sentiments, "neutral")
		val pos = getAverageSentiment(sentiments, "pos")

		val response = Json.obj("probability" -> Json.obj("neg" -> neg, "neutral" -> neutral, "pos" -> pos))

		val classification = if (neutral > 0.5) "neutral" else if (neg > pos) "neg" else "pos"

		val r = response + ("label" -> JsString(classification))
		logger.info(s"Response: [$r]")

		r
	}
}
