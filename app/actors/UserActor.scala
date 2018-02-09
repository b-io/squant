package actors

import javax.inject.{Inject, Named}

import actors.Messages.{Securities, UnwatchSecurities, WatchSecurities}
import akka.{Done, NotUsed}
import akka.actor.{Actor, ActorRef}
import akka.event.{Logging, LogMarker, MarkerLoggingAdapter}
import akka.stream.{KillSwitches, Materializer, UniqueKillSwitch}
import akka.stream.scaladsl.{BroadcastHub, Flow, Keep, MergeHub, RunnableGraph, Sink}
import akka.util.Timeout
import com.google.inject.assistedinject.Assisted
import finance.{Security, SecurityId}
import play.api.Configuration
import play.api.libs.json.{Json, JsValue}

import scala.concurrent.{ExecutionContext, Future}
import scala.concurrent.duration._

/**
  * Creates a user actor that sets up the WebSocket stream.  Although it's not required,
  * having an actor manage the stream helps with lifecycle and monitoring, and also helps
  * with dependency injection through the AkkaGuiceSupport trait.
  *
  * @param financeActor the actor responsible for securities and their streams
  * @param ec           the implicit CPU bound execution context
  */
class UserActor @Inject()(@Assisted id: String, @Named("financeActor") financeActor: ActorRef, config: Configuration)
		(implicit mat: Materializer, ec: ExecutionContext) extends Actor {
	// Useful way to mark out individual actors with WebSocket request context information...
	private val marker = LogMarker(name = self.path.name)
	implicit val logger: MarkerLoggingAdapter = Logging.withMarker(context.system, this.getClass)

	implicit val timeout: Timeout = Timeout(100.millis)

	val (hubSink, hubSource) = MergeHub.source[JsValue](perProducerBufferSize = 16)
			.toMat(BroadcastHub.sink(bufferSize = 256))(Keep.both)
			.run()

	private val securitiesMap: Map[SecurityId, UniqueKillSwitch] = Map.empty

	private val jsonSink: Sink[JsValue, Future[Done]] = Sink.foreach { json =>
		// When the user types in a security in the upper right corner, this is triggered
		val id = (json \ "id").as[SecurityId]
		addSecurities(Set(id))
	}

	// If this actor is killed directly, stop anything that we started running explicitly
	override def postStop(): Unit = {
		logger.info(marker, s"Kill the actor [$self]")
		unwatchSecurities(securitiesMap.keySet)
	}

	/**
	  * The receive block, useful if other actors want to manipulate the flow.
	  */
	override def receive: Receive = onMessage(securitiesMap)

	/**
	  * Generates a flow that can be used by the WebSocket.
	  *
	  * @return the flow of JSON
	  */
	private lazy val webSocketFlow: Flow[JsValue, JsValue, NotUsed] = {
		// Put the source and sink together to make a flow of hub source as output (aggregating all
		// securities as JSON to the browser) and the actor as the sink (receiving any JSON messages
		// from the browser), using a coupled sink and source
		Flow.fromSinkAndSourceCoupled(jsonSink, hubSource).watchTermination() { (_, termination) =>
			// When the flow shuts down, make sure this actor also stops
			termination.foreach { _ =>
				if (context != null) {
					logger.info(s"Stop the actor [$self]")
					context.stop(self)
				}
			}
			NotUsed
		}
	}

	/**
	  * Adds several securities to the hub, by asking the securities actor for securities.
	  */
	private def addSecurities(ids: Set[SecurityId]): Future[Unit] = {
		import akka.pattern.ask

		// Ask the financeActor for a stream containing these securities.
		val future = (financeActor ? WatchSecurities(ids)).mapTo[Securities]

		// when we get the response back, we want to turn that into a flow by creating a single
		// source and a single sink, so we merge all of the security sources together into one by
		// pointing them to the hubSink, so we can add them dynamically even after the flow
		// has started.
		future.map { (newSecurities: Securities) =>
			newSecurities.securities.foreach { security =>
				if (!securitiesMap.contains(security.id)) {
					logger.info(marker, s"Add the security [$security]")
					addSecurity(security)
				}
			}
		}
	}

	/**
	  * Adds a single security to the hub.
	  */
	private def addSecurity(security: Security): Unit = {
		// We convert everything to JsValue so we get a single stream for the WebSocket.
		// Make sure the history gets written out before the updates for this security...
		val historySource = security.history(config.get[String]("graph.size").toInt).map(Json.toJson(_))
		val updateSource = security.update.map(Json.toJson(_))
		val securitySource = historySource.concat(updateSource)

		// Set up a flow that will let us pull out a kill switch for this specific security,
		// and automatic cleanup for very slow subscribers (where the browser has crashed, etc.)
		val killSwitchFlow: Flow[JsValue, JsValue, UniqueKillSwitch] = {
			Flow.apply[JsValue]
					.joinMat(KillSwitches.singleBidi[JsValue, JsValue])(Keep.right)
					.backpressureTimeout(2.seconds)
		}

		// Set up a complete runnable graph from the security source to the hub's sink
		val graph: RunnableGraph[UniqueKillSwitch] = {
			securitySource.viaMat(killSwitchFlow)(Keep.right)
					.to(hubSink)
					.named(s"security-${ security.id }-$id")
		}

		// Start it up!
		val killSwitch = graph.run()

		// Pull out the kill switch so we can stop it when we want to unwatch a security
		context.become(onMessage(securitiesMap + (security.id -> killSwitch)))
	}

	def unwatchSecurities(ids: Set[SecurityId]): Unit = {
		ids.foreach { id =>
			securitiesMap.get(id).foreach { killSwitch =>
				logger.info(s"Unwatch the security [$id]")
				killSwitch.shutdown()
			}
			context.become(onMessage(securitiesMap - id))
		}
	}

	private def onMessage(securitiesMap: Map[SecurityId, UniqueKillSwitch]): Receive = {
		case WatchSecurities(ids) =>
			addSecurities(ids)
			sender() ! webSocketFlow

		case UnwatchSecurities(ids) =>
			unwatchSecurities(ids)
	}
}

/**
  * Sets the companion factory.
  *
  * @see https://blog.codecentric.de/en/2017/03/akka-best-practices-defining-actor-props/
  */
object UserActor {
	trait Factory {
		def apply(id: String): Actor
	}
}
