import java.text.{DateFormat, SimpleDateFormat}
import java.util.TimeZone

import scala.util.control.Exception.allCatch

def nonEmpty(o: Object): Boolean = o != null && o.toString().nonEmpty

def isDate(o: Object, format: DateFormat): Boolean = nonEmpty(o) &&
		(allCatch opt format.parse(o.toString)).isDefined

def isNumber(o: Object): Boolean = nonEmpty(o) && (allCatch opt o.toString.toDouble).isDefined

isNumber("2")
val format: DateFormat =  new SimpleDateFormat("yyyy-MM-dd hh:mm:ss")
format.setTimeZone(TimeZone.getTimeZone("UTC"))
isDate("", format)
