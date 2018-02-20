package controllers

import javax.inject.{Inject, Named, Singleton}

import actors.UserParentActor
import akka.NotUsed
import akka.actor.ActorRef
import akka.pattern.ask
import akka.stream.scaladsl.Flow
import akka.util.Timeout
import play.api.Logger
import play.api.libs.json.{Json, JsValue}
import play.api.mvc.{AbstractController, AnyContent, ControllerComponents, Request, RequestHeader, WebSocket}
import utils.Conf.HTTP

import scala.concurrent.{ExecutionContext, Future}
import scala.concurrent.duration._

/**
  * This class creates the actions and the WebSocket needed.
  */
@Singleton
class HomeController @Inject()(@Named("userParentActor") userParentActor: ActorRef, cc: ControllerComponents)
		(implicit ec: ExecutionContext) extends AbstractController(cc) with SameOriginCheck {
	val logger = Logger(getClass)

	// Home page that renders template
	def index = Action {
		implicit request: Request[AnyContent] => Ok(views.html.index())
	}

	/**
	  * Creates a WebSocket.
	  *
	  * @return a fully realized WebSocket
	  *
	  * @note acceptOrResult is preferable here because it returns a Future[Flow], which is required
	  *       internally.
	  */
	def ws: WebSocket = WebSocket.acceptOrResult[JsValue, JsValue] {
		case accepted if sameOriginCheck(accepted) => createFutureFlow(accepted)
				.map { flow => Right(flow) }
				.recover {
					case e: Exception =>
						logger.error(s"Request [$accepted] failed: Cannot create a WebSocket", e)
						val jsError = Json.obj("error" -> "Cannot create a WebSocket")
						val result = InternalServerError(jsError)
						Left(result)
				}
		case rejected =>
			logger.error(s"Request [$rejected] failed: Origin check failed")
			Future.successful {
				Left(Forbidden("Forbidden"))
			}
	}

	/**
	  * Creates a Future containing a Flow of JsValue in and out.
	  */
	private def createFutureFlow(request: RequestHeader): Future[Flow[JsValue, JsValue, NotUsed]] = {
		// Set the default timeout
		implicit val timeout: Timeout = Timeout(10.seconds)
		val future: Future[Any] = userParentActor ? UserParentActor.Create(request.id.toString)
		val futureFlow: Future[Flow[JsValue, JsValue, NotUsed]] = future.mapTo[Flow[JsValue, JsValue, NotUsed]]
		futureFlow
	}

}

trait SameOriginCheck {

	def logger: Logger

	/**
	  * Checks that the WebSocket comes from the same origin.
	  *
	  * @note This is necessary to protect against Cross-Site WebSocket Hijacking as WebSocket does not implement Same
	  *       Origin Policy.
	  * @see https://tools.ietf.org/html/rfc6455#section-1.3
	  * @see http://blog.dewhurstsecurity.com/2013/08/30/security-testing-html5-websockets.html
	  */
	def sameOriginCheck(rh: RequestHeader): Boolean = {
		rh.headers.get("Origin") match {
			case Some(originValue) if originMatches(originValue) => logger.debug(s"Check origin: [$originValue]")
				true
			case Some(badOrigin) => logger
					.error(s"Check origin: [$badOrigin] is not the same origin")
				false
			case None => logger.error("Check origin: No origin header found")
				false
		}
	}

	/**
	  * Returns true if the value of the origin header contains an acceptable value.
	  */
	def originMatches(origin: String): Boolean = {
		origin.contains(HTTP.LOCAL_URL) || origin.contains(HTTP.URL) || true
	}
}
