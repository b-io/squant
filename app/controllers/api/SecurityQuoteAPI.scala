package controllers.api

import javax.inject.{Inject, Singleton}

import controllers.SameOriginCheck
import play.api.Logger
import play.api.libs.json.{JsObject, Json, JsString}
import play.api.libs.ws.{WSClient, WSResponse}
import play.api.mvc.{AbstractController, Action, AnyContent, ControllerComponents, Result}
import utils.Conf.Finance.API

import scala.concurrent.{ExecutionContext, Future}

@Singleton
class SecurityQuoteAPI @Inject()(ws: WSClient, cc: ControllerComponents)(implicit ec: ExecutionContext)
		extends AbstractController(cc) with SameOriginCheck {
	val logger = Logger(getClass)

	def get(id: String): Action[AnyContent] = Action.async {
		val futureSecurityQuotes: Future[Result] = for {quotes <- getQuotes(id)} yield Ok(parseToJson(quotes))

		futureSecurityQuotes.recover {
			case _: NoSuchElementException => InternalServerError(
				Json.obj("error" -> JsString(s"[$id] Could not fetch the quotes"))
			)
		}
	}

	def getQuotesJson(id: String): Future[JsObject] = for {quotes <- getQuotes(id)} yield parseToJson(quotes)

	private def getQuotes(id: String): Future[WSResponse] = {
		val url = API.URL.format(id)
		logger.info(s"[$id] Get the latest quotes from [$url]")

		ws.url(url).get.withFilter { response => response.status == OK }
	}

	private def parseToJson(quotes: WSResponse): JsObject = {
		logger.info(s"Parse the quotes to JSON: [$quotes]")

		quotes.json.as[JsObject]
	}
}
