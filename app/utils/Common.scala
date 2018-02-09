package utils

object Common {
	implicit def ordered[A <% Comparable[_ >: A]]: Ordering[A] = (x: A, y: A) => x compareTo y
}
