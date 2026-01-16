package com.banking.controller;

import com.banking.model.Account;
import com.banking.service.BankingService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.hamcrest.Matchers.*;

@SpringBootTest
@ActiveProfiles("test")
@AutoConfigureMockMvc
@Transactional
class BankingControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private BankingService bankingService;

    private Account testAccount;

    @BeforeEach
    void setUp() {
        testAccount = bankingService.createAccount("Test User", BigDecimal.valueOf(5000));
    }

    @Test
    void testCreateAccount() throws Exception {
        mockMvc.perform(post("/api/accounts")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"accountName\":\"New User\",\"initialBalance\":1000.00}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.accountId").exists())
                .andExpect(jsonPath("$.accountName").value("New User"))
                .andExpect(jsonPath("$.balance").value(1000.00));
        
        System.out.println("Create account endpoint test passed");
    }

    @Test
    void testGetAccount() throws Exception {
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountId").value(testAccount.getAccountId()))
                .andExpect(jsonPath("$.accountName").value("Test User"))
                .andExpect(jsonPath("$.balance").value(5000));
        
        System.out.println("Get account endpoint test passed");
    }

    @Test
    void testGetAccountNotFound() throws Exception {
        mockMvc.perform(get("/api/accounts/999999"))
                .andExpect(status().isNotFound());
        
        System.out.println("Get account not found test passed");
    }

    @Test
    void testGetBalance() throws Exception {
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId() + "/balance"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.balance").value(5000));
        
        System.out.println("Get balance endpoint test passed");
    }

    @Test
    void testTransferMoney() throws Exception {
        Account toAccount = bankingService.createAccount("Receiver", BigDecimal.valueOf(1000));
        
        mockMvc.perform(post("/api/transactions/transfer")
                .contentType(MediaType.APPLICATION_JSON)
                .content(String.format("{\"fromAccountId\":%d,\"toAccountId\":%d,\"amount\":500}",
                        testAccount.getAccountId(), toAccount.getAccountId())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.fromAccountId").value(testAccount.getAccountId()))
                .andExpect(jsonPath("$.toAccountId").value(toAccount.getAccountId()))
                .andExpect(jsonPath("$.amount").value(500));
        
        System.out.println("Transfer money endpoint test passed");
    }

    @Test
    void testTransferMoneyInsufficientBalance() throws Exception {
        Account toAccount = bankingService.createAccount("Receiver", BigDecimal.valueOf(1000));
        
        mockMvc.perform(post("/api/transactions/transfer")
                .contentType(MediaType.APPLICATION_JSON)
                .content(String.format("{\"fromAccountId\":%d,\"toAccountId\":%d,\"amount\":10000}",
                        testAccount.getAccountId(), toAccount.getAccountId())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
        
        System.out.println("Transfer insufficient balance test passed");
    }

    @Test
    void testGetTransactionHistory() throws Exception {
        Account toAccount = bankingService.createAccount("Receiver", BigDecimal.valueOf(1000));
        bankingService.transferMoney(testAccount.getAccountId(), toAccount.getAccountId(), BigDecimal.valueOf(100));
        
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId() + "/transactions"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$", hasSize(greaterThanOrEqualTo(1))));
        
        System.out.println("Get transaction history endpoint test passed");
    }

    @Test
    void testRiskAnalysisEndpoint() throws Exception {
        long startTime = System.currentTimeMillis();
        
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId() + "/risk-analysis"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountId").value(testAccount.getAccountId()))
                .andExpect(jsonPath("$.expectedValue").exists())
                .andExpect(jsonPath("$.standardDeviation").exists())
                .andExpect(jsonPath("$.var95").exists())
                .andExpect(jsonPath("$.var99").exists())
                .andExpect(jsonPath("$.computationTimeMs").exists());
        
        long duration = System.currentTimeMillis() - startTime;
        System.out.println("Risk analysis endpoint test passed in " + duration + "ms");
    }

    @Test
    void testPortfolioOptimizationEndpoint() throws Exception {
        long startTime = System.currentTimeMillis();
        
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId() + "/portfolio-optimization"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountId").value(testAccount.getAccountId()))
                .andExpect(jsonPath("$.expectedReturn").exists())
                .andExpect(jsonPath("$.weights").isArray())
                .andExpect(jsonPath("$.computationTimeMs").exists());
        
        long duration = System.currentTimeMillis() - startTime;
        System.out.println("Portfolio optimization endpoint test passed in " + duration + "ms");
    }

    @Test
    void testFraudCheckEndpoint() throws Exception {
        long startTime = System.currentTimeMillis();
        
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId() + "/fraud-check?amount=5000"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountId").value(testAccount.getAccountId()))
                .andExpect(jsonPath("$.amount").value(5000))
                .andExpect(jsonPath("$.suspicious").exists())
                .andExpect(jsonPath("$.riskScore").exists())
                .andExpect(jsonPath("$.anomalyScore").exists())
                .andExpect(jsonPath("$.mlScore").exists())
                .andExpect(jsonPath("$.computationTimeMs").exists());
        
        long duration = System.currentTimeMillis() - startTime;
        System.out.println("Fraud check endpoint test passed in " + duration + "ms");
    }

    @Test
    void testDistributedPrimeSearchEndpoint() throws Exception {
        long startTime = System.currentTimeMillis();
        
        mockMvc.perform(get("/api/accounts/" + testAccount.getAccountId() + "/distributed-prime-search?rangeSize=50000"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountId").value(testAccount.getAccountId()))
                .andExpect(jsonPath("$.rangeSize").value(50000))
                .andExpect(jsonPath("$.totalPrimes").exists())
                .andExpect(jsonPath("$.computationTimeMs").exists())
                .andExpect(jsonPath("$.primesPerSecond").exists());
        
        long duration = System.currentTimeMillis() - startTime;
        System.out.println("Distributed prime search endpoint test passed in " + duration + "ms");
    }

    @Test
    void testHealthEndpoint() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
        
        System.out.println("Health endpoint test passed");
    }
}
