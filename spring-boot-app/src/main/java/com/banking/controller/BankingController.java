package com.banking.controller;

import com.banking.model.Account;
import com.banking.model.Transaction;
import com.banking.service.BankingService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class BankingController {
    
    @Autowired
    private BankingService bankingService;
    
    @Autowired
    private com.banking.service.ComputationalService computationalService;
    
    @PostMapping("/accounts")
    public ResponseEntity<Account> createAccount(@RequestBody Map<String, Object> request) {
        String accountName = (String) request.get("accountName");
        BigDecimal initialBalance = new BigDecimal(request.get("initialBalance").toString());
        
        Account account = bankingService.createAccount(accountName, initialBalance);
        return ResponseEntity.status(HttpStatus.CREATED).body(account);
    }
    
    @GetMapping("/accounts/{accountId}")
    public ResponseEntity<Account> getAccount(@PathVariable Long accountId) {
        return bankingService.getAccount(accountId)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }
    
    @GetMapping("/accounts/{accountId}/balance")
    public ResponseEntity<Map<String, BigDecimal>> getBalance(@PathVariable Long accountId) {
        BigDecimal balance = bankingService.getBalance(accountId);
        if (balance.compareTo(BigDecimal.ZERO) == 0 && bankingService.getAccount(accountId).isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(Map.of("balance", balance));
    }
    
    @PostMapping("/transactions/transfer")
    public ResponseEntity<?> transferMoney(@RequestBody Map<String, Object> request) {
        try {
            Long fromAccountId = Long.valueOf(request.get("fromAccountId").toString());
            Long toAccountId = Long.valueOf(request.get("toAccountId").toString());
            BigDecimal amount = new BigDecimal(request.get("amount").toString());
            
            Transaction transaction = bankingService.transferMoney(fromAccountId, toAccountId, amount);
            return ResponseEntity.ok(transaction);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }
    
    @GetMapping("/accounts/{accountId}/transactions")
    public ResponseEntity<List<Transaction>> getTransactionHistory(@PathVariable Long accountId) {
        List<Transaction> transactions = bankingService.getTransactionHistory(accountId);
        if (transactions.isEmpty() && bankingService.getAccount(accountId).isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(transactions);
    }
    
    @GetMapping("/accounts/{accountId}/risk-analysis")
    public ResponseEntity<?> performRiskAnalysis(@PathVariable Long accountId) {
        Account account = bankingService.getAccount(accountId)
            .orElseThrow(() -> new RuntimeException("Account not found"));
        
        // Pure CPU: Monte Carlo simulation with 15,000 iterations
        com.banking.service.ComputationalService.RiskAssessment risk = 
            computationalService.calculateRiskAssessment(
                accountId, 
                account.getBalance().doubleValue()
            );
        
        return ResponseEntity.ok(Map.of(
            "accountId", accountId,
            "expectedValue", risk.expectedValue,
            "standardDeviation", risk.standardDeviation,
            "var95", risk.var95,
            "var99", risk.var99,
            "computationTimeMs", risk.computationTimeNanos / 1_000_000.0
        ));
    }
    
    @GetMapping("/accounts/{accountId}/portfolio-optimization")
    public ResponseEntity<?> optimizePortfolio(@PathVariable Long accountId) {
        Account account = bankingService.getAccount(accountId)
            .orElseThrow(() -> new RuntimeException("Account not found"));
        
        // Pure CPU: Gradient descent with 2000 iterations
        com.banking.service.ComputationalService.PortfolioOptimization result = 
            computationalService.optimizePortfolio(
                accountId, 
                account.getBalance().doubleValue()
            );
        
        return ResponseEntity.ok(Map.of(
            "accountId", accountId,
            "expectedReturn", result.expectedReturn,
            "weights", result.weights,
            "computationTimeMs", result.computationTimeNanos / 1_000_000.0
        ));
    }
    
    @GetMapping("/accounts/{accountId}/fraud-check")
    public ResponseEntity<?> checkFraud(@PathVariable Long accountId, 
                                         @RequestParam(defaultValue = "1000") double amount) {
        if (!bankingService.getAccount(accountId).isPresent()) {
            return ResponseEntity.notFound().build();
        }
        
        // MULTI-THREADED: Parallel cryptographic hashing (8 competing threads)
        com.banking.service.ComputationalService.FraudCheckResult result = 
            computationalService.performFraudCheck(accountId, BigDecimal.valueOf(amount));
        
        return ResponseEntity.ok(Map.of(
            "accountId", accountId,
            "amount", amount,
            "suspicious", result.suspicious,
            "riskScore", result.riskScore,
            "anomalyScore", result.anomalyScore,
            "mlScore", result.mlScore,
            "computationTimeMs", result.computationTimeNanos / 1_000_000.0
        ));
    }
    
    @GetMapping("/accounts/{accountId}/distributed-prime-search")
    public ResponseEntity<?> distributedPrimeSearch(@PathVariable Long accountId,
                                                     @RequestParam(defaultValue = "100000") int rangeSize) {
        if (!bankingService.getAccount(accountId).isPresent()) {
            return ResponseEntity.notFound().build();
        }
        
        // MULTI-THREADED: Distributed prime search (12 competing threads)
        com.banking.service.ComputationalService.DistributedPrimeResult result = 
            computationalService.distributedPrimeSearch(accountId, rangeSize);
        
        return ResponseEntity.ok(Map.of(
            "accountId", accountId,
            "rangeSize", rangeSize,
            "totalPrimes", result.totalPrimes,
            "computationTimeMs", result.computationTimeNanos / 1_000_000.0,
            "primesPerSecond", (result.totalPrimes / (result.computationTimeNanos / 1_000_000_000.0))
        ));
    }
}
