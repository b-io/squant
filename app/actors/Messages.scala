package actors

import finance.{Security, SecurityId}

object Messages {
	case class Securities(securities: Set[Security]) {
		require(securities.nonEmpty, "Must specify at least one security!")
	}

	case class WatchSecurities(ids: Set[SecurityId]) {
		require(ids.nonEmpty, "Must specify at least one security!")
	}

	case class UnwatchSecurities(ids: Set[SecurityId]) {
		require(ids.nonEmpty, "Must specify at least one security!")
	}
}
