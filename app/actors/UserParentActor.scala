package actors

import javax.inject.Inject

import actors.Messages.WatchSecurities
import actors.UserParentActor.Create
import akka.actor.{Actor, ActorLogging, ActorRef}
import akka.event.LoggingReceive
import akka.pattern.{ask, pipe}
import akka.stream.scaladsl.Flow
import akka.util.Timeout
import play.api.Configuration
import play.api.libs.concurrent.InjectedActorSupport
import play.api.libs.json.JsValue
import finance.SecurityId

import scala.concurrent.ExecutionContext
import scala.concurrent.duration._

/**
  * Provide some DI and configuration sugar for new UserActor instances.
  */
class UserParentActor @Inject()(childFactory: UserActor.Factory, config: Configuration)
		(implicit ec: ExecutionContext) extends Actor with InjectedActorSupport with ActorLogging {
	implicit val timeout: Timeout = Timeout(5.seconds)

	private val defaultSecurities: Set[SecurityId] = config.get[Seq[String]]("finance.security.set")
			.map(SecurityId(_)).toSet

	override def receive: Receive = LoggingReceive {
		case Create(id) =>
			val name = s"userActor-$id"
			log.info(s"Create the user actor [$name] with the default securities [$defaultSecurities]")
			val child: ActorRef = injectedChild(childFactory(id), name)
			val future = (child ? WatchSecurities(defaultSecurities)).mapTo[Flow[JsValue, JsValue, _]]
			pipe(future) to sender()
	}
}

object UserParentActor {
	case class Create(id: String)
}
