import actors.{FinanceActor, UserActor, UserParentActor}
import com.google.inject.AbstractModule
import play.api.libs.concurrent.AkkaGuiceSupport
import utils.Conf

class Module extends AbstractModule with AkkaGuiceSupport {
	override def configure(): Unit = {
		bind(classOf[Conf]).asEagerSingleton()
		bindActor[FinanceActor]("financeActor")
		bindActor[UserParentActor]("userParentActor")
		bindActorFactory[UserActor, UserActor.Factory]
	}
}
