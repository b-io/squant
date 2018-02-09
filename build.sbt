name := "squant"

version := "1.0-SNAPSHOT"

lazy val root = (project in file(".")).enablePlugins(PlayScala)

val akkaVersion = "2.5.9"

scalaVersion := "2.12.4"

////////////////////////////////////////////////////////////////////////////////

libraryDependencies += guice
libraryDependencies += ws

libraryDependencies += "org.webjars" %% "webjars-play" % "2.6.3"
libraryDependencies += "org.webjars" % "bootstrap" % "3.3.6"
libraryDependencies += "org.webjars" % "flot" % "0.8.3"
libraryDependencies += "org.webjars" % "momentjs" % "2.20.1"

////////////////////////////////////////////////////////////////////////////////

libraryDependencies += "com.typesafe.akka" %% "akka-testkit" % akkaVersion % Test
libraryDependencies += "com.typesafe.akka" %% "akka-stream-testkit" % akkaVersion % Test
libraryDependencies += "org.scalatestplus.play" %% "scalatestplus-play" % "3.1.2" % Test
libraryDependencies += "org.awaitility" % "awaitility" % "3.0.0" % Test
