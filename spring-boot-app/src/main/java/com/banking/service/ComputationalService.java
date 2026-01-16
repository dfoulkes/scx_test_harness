package com.banking.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Random;
import java.util.concurrent.*;
import java.util.stream.IntStream;

/**
 * Pure CPU-intensive computational service to stress test schedulers
 * Multi-threaded parallel execution creates heavy thread contention
 * Forces scheduler to make complex thread ordering decisions
 */
@Service
public class ComputationalService {
    
    @Value("${fraud.detection.threshold:150}")
    private double fraudDetectionThreshold;
    
    private final ExecutorService parallelExecutor = Executors.newFixedThreadPool(24);
    
    private static final int HASH_ITERATIONS = 2000;
    private static final int MONTE_CARLO_SIMULATIONS = 15000;
    private static final int MATRIX_SIZE = 100;
    
    /**
     * CPU-intensive fraud detection with PARALLEL cryptographic hashing and pattern analysis
     * Spawns multiple competing threads to stress the scheduler
     */
    public FraudCheckResult performFraudCheck(Long accountId, BigDecimal amount) {
        long startTime = System.nanoTime();
        
        // Execute multiple CPU-intensive tasks in PARALLEL to create thread contention
        List<Future<Double>> futures = new ArrayList<>();
        
        // Spawn 8 parallel hashing tasks (competing threads)
        for (int i = 0; i < 8; i++) {
            final int taskId = i;
            futures.add(parallelExecutor.submit(() -> {
                String hash = computeIterativeHash(accountId.toString() + taskId, HASH_ITERATIONS / 4);
                return (double) hash.hashCode();
            }));
        }
        
        // Pattern matching with heavy computation (parallel)
        Future<Double> anomalyFuture = parallelExecutor.submit(() -> 
            calculateAnomalyScore(accountId, amount.doubleValue())
        );
        
        // Complex risk calculation (parallel)
        Future<Double> riskFuture = parallelExecutor.submit(() -> 
            calculateComplexRisk(amount.doubleValue(), 100.0)
        );
        
        // ML model inference (parallel)
        Future<Double> mlFuture = parallelExecutor.submit(() -> 
            simulateMLInference(accountId, amount.doubleValue())
        );
        
        // Wait for all parallel tasks to complete (thread synchronization point)
        try {
            double hashSum = 0;
            for (Future<Double> f : futures) {
                hashSum += f.get();
            }
            
            double anomalyScore = anomalyFuture.get();
            double riskScore = riskFuture.get();
            double mlScore = mlFuture.get();
            
            double totalScore = riskScore + mlScore + anomalyScore;
            // Threshold configurable: 150 (production) or 50000 (tests)
            boolean isSuspicious = totalScore > fraudDetectionThreshold;
            
            long duration = System.nanoTime() - startTime;
            
            return new FraudCheckResult(isSuspicious, riskScore, anomalyScore, mlScore, duration);
        } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException("Parallel computation failed", e);
        }
    }
    
    /**
     * Iterative SHA-256 hashing - pure CPU work
     */
    private String computeIterativeHash(String input, int iterations) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = input.getBytes();
            
            for (int i = 0; i < iterations; i++) {
                hash = digest.digest(hash);
                // Extra computation to prevent optimization
                for (int j = 0; j < hash.length; j++) {
                    hash[j] ^= (byte)(i % 256);
                }
            }
            
            return bytesToHex(hash);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }
    
    /**
     * Heavy statistical computation with transcendental functions
     */
    private double calculateAnomalyScore(Long accountId, double amount) {
        Random random = new Random(accountId);
        double score = 0.0;
        
        for (int i = 1; i <= 1000; i++) {
            double x = random.nextGaussian() * amount;
            
            // Heavy floating point operations
            score += Math.sin(x / i) * Math.cos(x * i);
            score += Math.log1p(Math.abs(x)) / Math.sqrt(i);
            score += Math.exp(-Math.abs(x) / 1000) * Math.pow(i, 0.3);
            score += Math.atan(x / i) * Math.sinh(x / 10000);
        }
        
        return Math.abs(score);
    }
    
    /**
     * Complex risk calculation with nested loops
     */
    private double calculateComplexRisk(double amount, double anomalyScore) {
        double risk = 0.0;
        
        // Nested loops for O(n²) complexity
        for (int i = 1; i <= 200; i++) {
            for (int j = 1; j <= 200; j++) {
                risk += Math.sqrt(amount / (i * j));
                risk += Math.log1p(anomalyScore * i) / j;
                risk += Math.pow(i, 0.5) * Math.pow(j, 0.3);
            }
        }
        
        return risk / 40000.0;
    }
    
    /**
     * Simulate ML model inference with matrix multiplication
     */
    private double simulateMLInference(Long accountId, double amount) {
        int size = 50;
        Random random = new Random(accountId);
        
        // Create random matrices
        double[][] matrix1 = new double[size][size];
        double[][] matrix2 = new double[size][size];
        
        for (int i = 0; i < size; i++) {
            for (int j = 0; j < size; j++) {
                matrix1[i][j] = random.nextGaussian() * amount / 1000;
                matrix2[i][j] = random.nextGaussian();
            }
        }
        
        // Matrix multiplication (O(n³))
        double[][] result = multiplyMatrices(matrix1, matrix2);
        
        // Sum all elements with activation function
        double sum = 0;
        for (int i = 0; i < size; i++) {
            for (int j = 0; j < size; j++) {
                sum += Math.tanh(result[i][j]); // Activation function
            }
        }
        
        return Math.abs(sum);
    }
    
    /**
     * Monte Carlo simulation for risk assessment - PARALLEL execution
     * Splits simulations across multiple threads to create scheduler contention
     */
    public RiskAssessment calculateRiskAssessment(Long accountId, double balance) {
        long startTime = System.nanoTime();
        
        // Split simulations across parallel threads
        int numThreads = 16;
        int simsPerThread = MONTE_CARLO_SIMULATIONS / numThreads;
        
        // Execute simulations in parallel using multiple competing threads
        List<Future<double[]>> futures = IntStream.range(0, numThreads)
            .mapToObj(threadId -> parallelExecutor.submit(() -> {
                double[] results = new double[simsPerThread];
                ThreadLocalRandom random = ThreadLocalRandom.current();
                
                for (int i = 0; i < simsPerThread; i++) {
                    double simBalance = balance;
                    
                    // Random walk with complex calculations
                    for (int step = 0; step < 100; step++) {
                        double drift = Math.sin(step * 0.1) * 0.05;
                        double volatility = Math.sqrt(step + 1) * 0.02;
                        double randomChange = random.nextGaussian() * volatility + drift;
                        
                        simBalance *= (1 + randomChange);
                        simBalance += Math.log1p(Math.abs(simBalance)) * Math.cos(step);
                    }
                    
                    results[i] = simBalance;
                }
                
                return results;
            }))
            .toList();
        
        // Collect results from all parallel threads
        double[] outcomes = new double[MONTE_CARLO_SIMULATIONS];
        try {
            int offset = 0;
            for (Future<double[]> future : futures) {
                double[] threadResults = future.get();
                System.arraycopy(threadResults, 0, outcomes, offset, threadResults.length);
                offset += threadResults.length;
            }
        } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException("Parallel Monte Carlo failed", e);
        }
        
        // Statistical analysis
        Arrays.sort(outcomes);
        double mean = calculateMean(outcomes);
        double stdDev = calculateStdDev(outcomes, mean);
        double var95 = outcomes[(int)(outcomes.length * 0.05)];
        double var99 = outcomes[(int)(outcomes.length * 0.01)];
        
        long duration = System.nanoTime() - startTime;
        
        return new RiskAssessment(mean, stdDev, var95, var99, duration);
    }
    
    /**
     * Portfolio optimization using PARALLEL gradient descent
     * Multiple threads optimize different portfolios simultaneously
     */
    public PortfolioOptimization optimizePortfolio(Long accountId, double balance) {
        long startTime = System.nanoTime();
        
        int numAssets = 20;
        int numParallelOptimizations = 8;  // Run 8 parallel optimizations
        
        // Execute multiple portfolio optimizations in parallel (heavy thread contention)
        List<Future<PortfolioResult>> futures = IntStream.range(0, numParallelOptimizations)
            .mapToObj(portfolioId -> parallelExecutor.submit(() -> {
                double[] weights = new double[numAssets];
                double[] expectedReturns = new double[numAssets];
                double[][] covarianceMatrix = new double[numAssets][numAssets];
                
                Random random = new Random(accountId + portfolioId);
                
                // Initialize
                for (int i = 0; i < numAssets; i++) {
                    weights[i] = 1.0 / numAssets;
                    expectedReturns[i] = random.nextGaussian() * 0.15 + 0.08;
                }
                
                // Generate covariance matrix
                for (int i = 0; i < numAssets; i++) {
                    for (int j = 0; j < numAssets; j++) {
                        covarianceMatrix[i][j] = random.nextGaussian() * 0.01;
                        if (i == j) covarianceMatrix[i][j] += 0.04;
                    }
                }
                
                // Gradient descent optimization
                for (int iter = 0; iter < 2000; iter++) {
                    double portfolioReturn = 0;
                    double portfolioRisk = 0;
                    
                    for (int i = 0; i < numAssets; i++) {
                        portfolioReturn += weights[i] * expectedReturns[i];
                        for (int j = 0; j < numAssets; j++) {
                            portfolioRisk += weights[i] * weights[j] * covarianceMatrix[i][j];
                        }
                    }
                    
                    portfolioRisk = Math.sqrt(portfolioRisk);
                    
                    for (int i = 0; i < numAssets; i++) {
                        double gradient = expectedReturns[i] / portfolioRisk;
                        weights[i] += 0.001 * gradient;
                        weights[i] = Math.max(0, Math.min(1, weights[i]));
                    }
                    
                    double sum = Arrays.stream(weights).sum();
                    for (int i = 0; i < numAssets; i++) {
                        weights[i] /= sum;
                    }
                }
                
                double finalReturn = Arrays.stream(weights)
                    .reduce(0, (acc, w) -> acc + w * expectedReturns[(int)acc % numAssets]);
                
                return new PortfolioResult(finalReturn, weights);
            }))
            .toList();
        
        // Wait for all parallel optimizations and pick best
        try {
            PortfolioResult best = null;
            double bestReturn = Double.NEGATIVE_INFINITY;
            
            for (Future<PortfolioResult> future : futures) {
                PortfolioResult result = future.get();
                if (result.expectedReturn > bestReturn) {
                    bestReturn = result.expectedReturn;
                    best = result;
                }
            }
            
            long duration = System.nanoTime() - startTime;
            return new PortfolioOptimization(best.expectedReturn, best.weights, duration);
            
        } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException("Parallel optimization failed", e);
        }
    }
    
    private static class PortfolioResult {
        final double expectedReturn;
        final double[] weights;
        
        PortfolioResult(double expectedReturn, double[] weights) {
            this.expectedReturn = expectedReturn;
            this.weights = weights;
        }
    }
    
    /**
     * Distributed prime number search across multiple threads
     * Creates heavy thread contention and synchronization overhead
     */
    public DistributedPrimeResult distributedPrimeSearch(Long accountId, int rangeSize) {
        long startTime = System.nanoTime();
        
        int numThreads = 12;
        long baseNum = accountId * 1000;
        long rangePerThread = rangeSize / numThreads;
        
        // Parallel prime search across multiple competing threads
        List<Future<List<Long>>> futures = IntStream.range(0, numThreads)
            .mapToObj(threadId -> parallelExecutor.submit(() -> {
                List<Long> primes = new ArrayList<>();
                long start = baseNum + (threadId * rangePerThread);
                long end = start + rangePerThread;
                
                for (long num = start; num < end; num++) {
                    if (isPrime(num)) {
                        primes.add(num);
                    }
                }
                
                return primes;
            }))
            .toList();
        
        // Collect all primes from parallel threads
        try {
            List<Long> allPrimes = new ArrayList<>();
            for (Future<List<Long>> future : futures) {
                allPrimes.addAll(future.get());
            }
            
            long duration = System.nanoTime() - startTime;
            return new DistributedPrimeResult(allPrimes.size(), allPrimes, duration);
            
        } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException("Parallel prime search failed", e);
        }
    }
    
    /**
     * Prime number calculation for account validation (CPU-intensive)
     */
    public boolean isPrimeAccount(Long accountId) {
        // Find nth prime where n = accountId % 10000
        int n = (int)(accountId % 10000) + 1000;
        return findNthPrime(n) % 2 == 1;
    }
    
    private long findNthPrime(int n) {
        int count = 0;
        long num = 2;
        
        while (count < n) {
            if (isPrime(num)) {
                count++;
            }
            num++;
        }
        
        return num - 1;
    }
    
    private boolean isPrime(long n) {
        if (n <= 1) return false;
        if (n <= 3) return true;
        if (n % 2 == 0 || n % 3 == 0) return false;
        
        for (long i = 5; i * i <= n; i += 6) {
            if (n % i == 0 || n % (i + 2) == 0) return false;
        }
        
        return true;
    }
    
    // Helper methods
    
    private double[][] multiplyMatrices(double[][] a, double[][] b) {
        int n = a.length;
        double[][] result = new double[n][n];
        
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                for (int k = 0; k < n; k++) {
                    result[i][j] += a[i][k] * b[k][j];
                }
            }
        }
        
        return result;
    }
    
    private double calculateMean(double[] values) {
        double sum = 0;
        for (double v : values) sum += v;
        return sum / values.length;
    }
    
    private double calculateStdDev(double[] values, double mean) {
        double sumSquaredDiff = 0;
        for (double v : values) {
            double diff = v - mean;
            sumSquaredDiff += diff * diff;
        }
        return Math.sqrt(sumSquaredDiff / values.length);
    }
    
    private String bytesToHex(byte[] bytes) {
        StringBuilder hex = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            hex.append(String.format("%02x", b));
        }
        return hex.toString();
    }
    
    // Result classes
    
    public static class FraudCheckResult {
        public final boolean suspicious;
        public final double riskScore;
        public final double anomalyScore;
        public final double mlScore;
        public final long computationTimeNanos;
        
        public FraudCheckResult(boolean suspicious, double riskScore, double anomalyScore, double mlScore, long computationTimeNanos) {
            this.suspicious = suspicious;
            this.riskScore = riskScore;
            this.anomalyScore = anomalyScore;
            this.mlScore = mlScore;
            this.computationTimeNanos = computationTimeNanos;
        }
    }
    
    public static class RiskAssessment {
        public final double expectedValue;
        public final double standardDeviation;
        public final double var95;
        public final double var99;
        public final long computationTimeNanos;
        
        public RiskAssessment(double expectedValue, double standardDeviation, double var95, double var99, long computationTimeNanos) {
            this.expectedValue = expectedValue;
            this.standardDeviation = standardDeviation;
            this.var95 = var95;
            this.var99 = var99;
            this.computationTimeNanos = computationTimeNanos;
        }
    }
    
    public static class PortfolioOptimization {
        public final double expectedReturn;
        public final double[] weights;
        public final long computationTimeNanos;
        
        public PortfolioOptimization(double expectedReturn, double[] weights, long computationTimeNanos) {
            this.expectedReturn = expectedReturn;
            this.weights = weights;
            this.computationTimeNanos = computationTimeNanos;
        }
    }
    
    public static class DistributedPrimeResult {
        public final int totalPrimes;
        public final List<Long> primes;
        public final long computationTimeNanos;
        
        public DistributedPrimeResult(int totalPrimes, List<Long> primes, long computationTimeNanos) {
            this.totalPrimes = totalPrimes;
            this.primes = primes;
            this.computationTimeNanos = computationTimeNanos;
        }
    }
}
