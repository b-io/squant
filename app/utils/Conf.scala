package utils

import javax.inject.{Inject, Singleton}

import com.typesafe.config.{Config, ConfigFactory}
import play.api.inject.Injector
import utils.Dates.{Date, DateFormatter}

@Singleton
class Conf @Inject()(injector: Injector) {
	Conf.INJECTOR = injector
}

object Conf {
	val CONFIG: Config = ConfigFactory.load()
	var INJECTOR: Injector = _

	object Finance {
		object API {
			val DATE_FORMATTER: DateFormatter = Dates
					.formatter(CONFIG.getString("finance.api.date.format"), CONFIG.getString("finance.api.date.zone"))
			val FROM_DATE: Date = Dates.convert(System.currentTimeMillis - CONFIG.getLong("finance.api.from.date"))
			val REFRESH_TIME: Int = CONFIG.getInt("finance.api.refresh.time")

			val URL: String = CONFIG.getString("finance.api.url")

			// The labels (column names) of the API output
			val ERROR: String = CONFIG.getString("finance.api.out.error")
			val META_DATA: String = CONFIG.getString("finance.api.out.meta.data")
			val DATA: String = CONFIG.getString("finance.api.out.data")
			val PRICE: String = CONFIG.getString("finance.api.out.price")
			val VOLUME: String = CONFIG.getString("finance.api.out.volume")
			val CAP: String = CONFIG.getString("finance.api.out.cap")
		}
	}

	object Graph {
		val SIZE: Int = CONFIG.getInt("graph.size")
	}

	object HTTP {
		val LOCAL_URL: String = CONFIG.getString("http.local.url")
		val URL: String = CONFIG.getString("http.url")
	}

	object Sentiment {
		object API {
			val URL: String = CONFIG.getString("sentiment.api.url")
		}
	}

	object Tweet {
		object API {
			val URL: String = CONFIG.getString("tweet.api.url")
		}
	}
}
