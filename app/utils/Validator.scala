package utils

import utils.Dates.DateFormatter

import scala.util.control.Exception.allCatch

object Validator {
	def nonEmpty(o: Object): Boolean = o != null && o.toString().nonEmpty

	def isDate(o: Object, formatter: DateFormatter): Boolean = (allCatch opt Dates.parse(o.toString, formatter))
			.isDefined

	def isNumber(o: Object): Boolean = (allCatch opt o.toString.toDouble).isDefined
}
