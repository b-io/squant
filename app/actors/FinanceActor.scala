package actors

import actors.Messages.{Securities, WatchSecurities}
import akka.actor.{Actor, ActorLogging}
import akka.event.LoggingReceive
import finance.{Security, SecurityId}

import scala.collection.mutable

/**
  * This actor contains a set of securities internally that may be used by all WebSocket clients.
  */
class FinanceActor extends Actor with ActorLogging {
	// @todo May want to remove securities that aren't viewed by any clients...
	private val securitiesMap: mutable.Map[SecurityId, Security] = mutable.HashMap()

	def receive = LoggingReceive {
		case WatchSecurities(ids) =>
			val securities = ids.map(id => securitiesMap.getOrElseUpdate(id, new Security(id)))
			sender ! Securities(securities)
	}
}
