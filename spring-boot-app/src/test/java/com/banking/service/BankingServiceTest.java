package com.banking.service;

import com.banking.model.Account;
import com.banking.model.Transaction;
import com.banking.repository.AccountRepository;
import com.banking.repository.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class BankingServiceTest {

    @Autowired
    private BankingService bankingService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @BeforeEach
    void setUp() {
        // Clean up before each test
        transactionRepository.deleteAll();
        accountRepository.deleteAll();
    }

    @Test
    void testCreateAccount() {
        String accountName = "Test User";
        BigDecimal initialBalance = BigDecimal.valueOf(1000.00);
        
        Account account = bankingService.createAccount(accountName, initialBalance);
        
        assertNotNull(account);
        assertNotNull(account.getAccountId());
        assertEquals(accountName, account.getAccountName());
        assertEquals(initialBalance, account.getBalance());
        
        System.out.println("Created account: " + account.getAccountId() + " with balance " + account.getBalance());
    }

    @Test
    void testGetAccount() {
        Account created = bankingService.createAccount("Test User", BigDecimal.valueOf(500));
        
        Optional<Account> retrieved = bankingService.getAccount(created.getAccountId());
        
        assertTrue(retrieved.isPresent());
        assertEquals(created.getAccountId(), retrieved.get().getAccountId());
        assertEquals(created.getAccountName(), retrieved.get().getAccountName());
    }

    @Test
    void testGetBalance() {
        BigDecimal initialBalance = BigDecimal.valueOf(2500.50);
        Account account = bankingService.createAccount("Balance Test", initialBalance);
        
        BigDecimal balance = bankingService.getBalance(account.getAccountId());
        
        assertEquals(initialBalance, balance);
    }

    @Test
    void testTransferMoneySuccess() {
        // Create two accounts
        Account fromAccount = bankingService.createAccount("Sender", BigDecimal.valueOf(1000));
        Account toAccount = bankingService.createAccount("Receiver", BigDecimal.valueOf(500));
        
        BigDecimal transferAmount = BigDecimal.valueOf(300);
        
        // Perform transfer (includes CPU-intensive fraud detection)
        Transaction transaction = bankingService.transferMoney(
            fromAccount.getAccountId(), 
            toAccount.getAccountId(), 
            transferAmount
        );
        
        assertNotNull(transaction);
        assertEquals(fromAccount.getAccountId(), transaction.getFromAccountId());
        assertEquals(toAccount.getAccountId(), transaction.getToAccountId());
        assertEquals(transferAmount, transaction.getAmount());
        assertEquals("TRANSFER", transaction.getTransactionType());
        
        // Verify balances updated
        BigDecimal fromBalance = bankingService.getBalance(fromAccount.getAccountId());
        BigDecimal toBalance = bankingService.getBalance(toAccount.getAccountId());
        
        assertEquals(BigDecimal.valueOf(700), fromBalance);
        assertEquals(BigDecimal.valueOf(800), toBalance);
        
        System.out.println("Transfer successful: " + transferAmount + " from " + fromAccount.getAccountId() + " to " + toAccount.getAccountId());
    }

    @Test
    void testTransferMoneyInsufficientBalance() {
        Account fromAccount = bankingService.createAccount("Poor Sender", BigDecimal.valueOf(100));
        Account toAccount = bankingService.createAccount("Rich Receiver", BigDecimal.valueOf(1000));
        
        BigDecimal transferAmount = BigDecimal.valueOf(500);
        
        assertThrows(RuntimeException.class, () -> {
            bankingService.transferMoney(
                fromAccount.getAccountId(), 
                toAccount.getAccountId(), 
                transferAmount
            );
        });
        
        // Verify balances unchanged
        assertEquals(BigDecimal.valueOf(100), bankingService.getBalance(fromAccount.getAccountId()));
        assertEquals(BigDecimal.valueOf(1000), bankingService.getBalance(toAccount.getAccountId()));
        
        System.out.println("Insufficient balance test passed");
    }

    @Test
    void testTransferMoneyInvalidAmount() {
        Account fromAccount = bankingService.createAccount("Sender", BigDecimal.valueOf(1000));
        Account toAccount = bankingService.createAccount("Receiver", BigDecimal.valueOf(500));
        
        assertThrows(IllegalArgumentException.class, () -> {
            bankingService.transferMoney(
                fromAccount.getAccountId(), 
                toAccount.getAccountId(), 
                BigDecimal.valueOf(-100)
            );
        });
        
        assertThrows(IllegalArgumentException.class, () -> {
            bankingService.transferMoney(
                fromAccount.getAccountId(), 
                toAccount.getAccountId(), 
                BigDecimal.ZERO
            );
        });
        
        System.out.println("Invalid amount test passed");
    }

    @Test
    void testTransferMoneyAccountNotFound() {
        Account account = bankingService.createAccount("Test User", BigDecimal.valueOf(1000));
        
        assertThrows(RuntimeException.class, () -> {
            bankingService.transferMoney(
                account.getAccountId(), 
                999999L, // Non-existent account
                BigDecimal.valueOf(100)
            );
        });
        
        assertThrows(RuntimeException.class, () -> {
            bankingService.transferMoney(
                999999L, // Non-existent account
                account.getAccountId(), 
                BigDecimal.valueOf(100)
            );
        });
        
        System.out.println("Account not found test passed");
    }

    @Test
    void testGetTransactionHistory() {
        // Create accounts and perform multiple transfers
        Account account1 = bankingService.createAccount("User1", BigDecimal.valueOf(5000));
        Account account2 = bankingService.createAccount("User2", BigDecimal.valueOf(3000));
        Account account3 = bankingService.createAccount("User3", BigDecimal.valueOf(2000));
        
        bankingService.transferMoney(account1.getAccountId(), account2.getAccountId(), BigDecimal.valueOf(100));
        bankingService.transferMoney(account1.getAccountId(), account3.getAccountId(), BigDecimal.valueOf(200));
        bankingService.transferMoney(account2.getAccountId(), account1.getAccountId(), BigDecimal.valueOf(50));
        
        List<Transaction> history = bankingService.getTransactionHistory(account1.getAccountId());
        
        assertNotNull(history);
        assertEquals(3, history.size());
        
        System.out.println("Transaction history for account " + account1.getAccountId() + ": " + history.size() + " transactions");
    }

    @Test
    void testLargeTransferTriggersRiskAssessment() {
        // Large transfers (>$1000) trigger CPU-intensive risk assessment
        Account fromAccount = bankingService.createAccount("Big Spender", BigDecimal.valueOf(10000));
        Account toAccount = bankingService.createAccount("Big Receiver", BigDecimal.valueOf(5000));
        
        BigDecimal largeAmount = BigDecimal.valueOf(5000);
        
        long startTime = System.currentTimeMillis();
        Transaction transaction = bankingService.transferMoney(
            fromAccount.getAccountId(), 
            toAccount.getAccountId(), 
            largeAmount
        );
        long duration = System.currentTimeMillis() - startTime;
        
        assertNotNull(transaction);
        assertEquals(largeAmount, transaction.getAmount());
        
        System.out.println("Large transfer with risk assessment completed in " + duration + "ms");
    }

    @Test
    void testMultipleConcurrentTransfers() throws InterruptedException {
        // Test thread contention with concurrent transfers
        Account mainAccount = bankingService.createAccount("Main Account", BigDecimal.valueOf(100000));
        
        int numAccounts = 10;
        Account[] accounts = new Account[numAccounts];
        for (int i = 0; i < numAccounts; i++) {
            accounts[i] = bankingService.createAccount("Account " + i, BigDecimal.valueOf(1000));
        }
        
        Thread[] threads = new Thread[numAccounts];
        for (int i = 0; i < numAccounts; i++) {
            final int index = i;
            threads[i] = new Thread(() -> {
                try {
                    bankingService.transferMoney(
                        mainAccount.getAccountId(),
                        accounts[index].getAccountId(),
                        BigDecimal.valueOf(500)
                    );
                } catch (Exception e) {
                    // Some may fail due to fraud detection
                    System.out.println("Transfer " + index + " failed: " + e.getMessage());
                }
            });
            threads[i].start();
        }
        
        for (Thread thread : threads) {
            thread.join();
        }
        
        System.out.println("Completed " + numAccounts + " concurrent transfers");
    }
}
