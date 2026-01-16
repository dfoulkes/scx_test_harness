package simulations

import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scala.concurrent.duration._

class BankingTransactionSimulation extends Simulation {

  val httpProtocol = http
    .baseUrl(System.getProperty("baseUrl", "http://localhost:8080"))
    .acceptHeader("application/json")
    .contentTypeHeader("application/json")

  // Simple feeders for test data
  val accountIdFeeder = Iterator.continually(Map("accountId" -> scala.util.Random.nextInt(1000)))
  val amountFeeder = Iterator.continually(Map("amount" -> (scala.util.Random.nextInt(2000) + 1000)))
  val userNameFeeder = Iterator.continually(Map("userName" -> s"User${scala.util.Random.nextInt(1000000)}"))

  val createAccountScenario = scenario("Create Account")
    .feed(userNameFeeder)
    .exec(http("Create Account")
      .post("/api/accounts")
      .body(StringBody("""{"accountName": "${userName}", "initialBalance": 10000.00}""")).asJson
      .check(status.is(201)))
    .pause(1)

  // CPU-INTENSIVE: Transfer with fraud detection and risk assessment
  val transferScenario = scenario("CPU-Heavy Transfer with Fraud Detection")
    .feed(accountIdFeeder)
    .feed(amountFeeder)
    .exec(http("Transfer Money")
      .post("/api/transactions/transfer")
      .body(StringBody("""{"fromAccountId": ${accountId}, "toAccountId": ${accountId}, "amount": ${amount}}""")).asJson
      .check(status.in(200, 400, 404)))
    .pause(100.milliseconds)

  // CPU-INTENSIVE: Monte Carlo simulation with 15,000 iterations
  val riskAnalysisScenario = scenario("Risk Analysis - Monte Carlo")
    .feed(accountIdFeeder)
    .exec(http("Risk Analysis")
      .get("/api/accounts/${accountId}/risk-analysis")
      .check(status.in(200, 404)))
    .pause(100.milliseconds)

  // CPU-INTENSIVE: Portfolio optimization with 2000 gradient descent iterations
  val portfolioOptScenario = scenario("Portfolio Optimization")
    .feed(accountIdFeeder)
    .exec(http("Portfolio Optimization")
      .get("/api/accounts/${accountId}/portfolio-optimization")
      .check(status.in(200, 404)))
    .pause(100.milliseconds)

  // CPU-INTENSIVE: Cryptographic hashing and pattern analysis (8 parallel threads)
  val fraudCheckScenario = scenario("Fraud Detection - Multi-threaded")
    .feed(accountIdFeeder)
    .exec(http("Fraud Check")
      .get("/api/accounts/${accountId}/fraud-check?amount=5000")
      .check(status.in(200, 404)))
    .pause(50.milliseconds)

  // CPU-INTENSIVE: Distributed prime search (12 parallel threads)
  val distributedPrimeScenario = scenario("Distributed Prime Search")
    .feed(accountIdFeeder)
    .exec(http("Prime Search")
      .get("/api/accounts/${accountId}/distributed-prime-search?rangeSize=100000")
      .check(status.in(200, 404)))
    .pause(100.milliseconds)

  val checkBalanceScenario = scenario("Check Balance")
    .feed(accountIdFeeder)
    .exec(http("Get Balance")
      .get("/api/accounts/${accountId}/balance")
      .check(status.in(200, 404)))
    .pause(2)

  val transactionHistoryScenario = scenario("Transaction History")
    .feed(accountIdFeeder)
    .exec(http("Get Transaction History")
      .get("/api/accounts/${accountId}/transactions")
      .check(status.in(200, 404)))
    .pause(1)

  setUp(
    // Initial account creation
    createAccountScenario.inject(
      rampUsersPerSec(1).to(10).during(30.seconds),
      constantUsersPerSec(10).during(2.minutes),
      rampUsersPerSec(10).to(1).during(30.seconds)
    ),
    // CPU-INTENSIVE: Transfer with fraud detection (2000 SHA-256 hashes + risk assessment)
    transferScenario.inject(
      rampUsersPerSec(5).to(20).during(30.seconds),
      constantUsersPerSec(20).during(2.minutes),
      rampUsersPerSec(20).to(5).during(30.seconds)
    ),
    // CPU-INTENSIVE: Monte Carlo simulation (15,000 iterations)
    riskAnalysisScenario.inject(
      rampUsersPerSec(2).to(10).during(30.seconds),
      constantUsersPerSec(10).during(2.minutes),
      rampUsersPerSec(10).to(2).during(30.seconds)
    ),
    // CPU-INTENSIVE: Portfolio optimization (2000 gradient descent iterations)
    portfolioOptScenario.inject(
      rampUsersPerSec(2).to(8).during(30.seconds),
      constantUsersPerSec(8).during(2.minutes),
      rampUsersPerSec(8).to(2).during(30.seconds)
    ),
    // CPU-INTENSIVE: Fraud detection (8 threads per request)
    fraudCheckScenario.inject(
      rampUsersPerSec(5).to(15).during(30.seconds),
      constantUsersPerSec(15).during(2.minutes),
      rampUsersPerSec(15).to(5).during(30.seconds)
    ),
    // CPU-INTENSIVE: Distributed prime search (12 threads per request)
    distributedPrimeScenario.inject(
      rampUsersPerSec(2).to(8).during(30.seconds),
      constantUsersPerSec(8).during(2.minutes),
      rampUsersPerSec(8).to(2).during(30.seconds)
    ),
    // Lighter load for balance checks
    checkBalanceScenario.inject(
      rampUsersPerSec(5).to(30).during(30.seconds),
      constantUsersPerSec(30).during(2.minutes),
      rampUsersPerSec(30).to(5).during(30.seconds)
    ),
    // Transaction history
    transactionHistoryScenario.inject(
      rampUsersPerSec(2).to(10).during(30.seconds),
      constantUsersPerSec(10).during(2.minutes),
      rampUsersPerSec(10).to(2).during(30.seconds)
    )
  ).protocols(httpProtocol)
    .maxDuration(4.minutes)
    .assertions(
      global.responseTime.max.lt(10000),  // Increased timeout for CPU-heavy operations
      global.successfulRequests.percent.gt(90)  // Slightly lower success rate due to heavy load
    )
}
