package com.banking.service;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@ActiveProfiles("test")
class ComputationalServiceTest {

    @Autowired
    private ComputationalService computationalService;

    @Test
    void testFraudCheckPerformance() {
        Long accountId = 12345L;
        BigDecimal amount = BigDecimal.valueOf(5000);
        
        long startTime = System.currentTimeMillis();
        ComputationalService.FraudCheckResult result = computationalService.performFraudCheck(accountId, amount);
        long duration = System.currentTimeMillis() - startTime;
        
        assertNotNull(result);
        assertTrue(result.riskScore >= 0);
        assertTrue(result.anomalyScore >= 0);
        assertTrue(result.mlScore >= 0);
        assertTrue(result.computationTimeNanos > 0);
        
        System.out.println("Fraud check completed in " + duration + "ms");
        System.out.println("  Risk Score: " + result.riskScore);
        System.out.println("  Anomaly Score: " + result.anomalyScore);
        System.out.println("  ML Score: " + result.mlScore);
        System.out.println("  Suspicious: " + result.suspicious);
    }

    @Test
    void testRiskAssessmentParallel() {
        Long accountId = 54321L;
        double balance = 10000.0;
        
        long startTime = System.currentTimeMillis();
        ComputationalService.RiskAssessment result = computationalService.calculateRiskAssessment(accountId, balance);
        long duration = System.currentTimeMillis() - startTime;
        
        assertNotNull(result);
        assertTrue(result.expectedValue > 0);
        assertTrue(result.standardDeviation >= 0);
        assertTrue(result.computationTimeNanos > 0);
        
        System.out.println("Risk assessment (15,000 simulations) completed in " + duration + "ms");
        System.out.println("  Expected Value: " + result.expectedValue);
        System.out.println("  Std Dev: " + result.standardDeviation);
        System.out.println("  VaR 95%: " + result.var95);
        System.out.println("  VaR 99%: " + result.var99);
    }

    @Test
    void testPortfolioOptimizationParallel() {
        Long accountId = 99999L;
        double balance = 50000.0;
        
        long startTime = System.currentTimeMillis();
        ComputationalService.PortfolioOptimization result = computationalService.optimizePortfolio(accountId, balance);
        long duration = System.currentTimeMillis() - startTime;
        
        assertNotNull(result);
        assertNotNull(result.weights);
        assertEquals(20, result.weights.length);
        assertTrue(result.computationTimeNanos > 0);
        
        // Check weights sum to approximately 1
        double sum = 0;
        for (double w : result.weights) {
            sum += w;
            assertTrue(w >= 0 && w <= 1, "Weight should be between 0 and 1");
        }
        assertEquals(1.0, sum, 0.01, "Weights should sum to 1");
        
        System.out.println("Portfolio optimization (8 parallel runs, 2000 iterations each) completed in " + duration + "ms");
        System.out.println("  Expected Return: " + result.expectedReturn);
    }

    @Test
    void testDistributedPrimeSearch() {
        Long accountId = 11111L;
        int rangeSize = 50000;
        
        long startTime = System.currentTimeMillis();
        ComputationalService.DistributedPrimeResult result = computationalService.distributedPrimeSearch(accountId, rangeSize);
        long duration = System.currentTimeMillis() - startTime;
        
        assertNotNull(result);
        assertTrue(result.totalPrimes > 0);
        assertNotNull(result.primes);
        assertEquals(result.totalPrimes, result.primes.size());
        assertTrue(result.computationTimeNanos > 0);
        
        System.out.println("Distributed prime search (12 parallel threads, range=" + rangeSize + ") completed in " + duration + "ms");
        System.out.println("  Total Primes Found: " + result.totalPrimes);
        System.out.println("  Primes/sec: " + (result.totalPrimes / (duration / 1000.0)));
    }

    @Test
    void testMultipleConcurrentFraudChecks() throws InterruptedException {
        // Test thread contention by running multiple fraud checks concurrently
        int numConcurrent = 10;
        Thread[] threads = new Thread[numConcurrent];
        
        for (int i = 0; i < numConcurrent; i++) {
            final long accountId = 10000L + i;
            threads[i] = new Thread(() -> {
                ComputationalService.FraudCheckResult result = 
                    computationalService.performFraudCheck(accountId, BigDecimal.valueOf(1000 + accountId));
                assertNotNull(result);
            });
            threads[i].start();
        }
        
        // Wait for all threads to complete
        for (Thread thread : threads) {
            thread.join();
        }
        
        System.out.println("Successfully completed " + numConcurrent + " concurrent fraud checks");
    }

    @Test
    void testIsPrimeAccount() {
        Long accountId = 12345L;
        
        boolean result = computationalService.isPrimeAccount(accountId);
        
        assertNotNull(result);
        System.out.println("Account " + accountId + " prime check: " + result);
    }
}
