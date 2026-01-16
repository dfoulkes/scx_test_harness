package com.banking.service;

import com.banking.model.Account;
import com.banking.model.Transaction;
import com.banking.repository.AccountRepository;
import com.banking.repository.TransactionRepository;
import com.banking.kafka.KafkaProducerService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

@Service
public class BankingService {
    
    @Autowired
    private AccountRepository accountRepository;
    
    @Autowired
    private TransactionRepository transactionRepository;
    
    @Autowired(required = false)
    private KafkaProducerService kafkaProducerService;
    
    @Autowired
    private ComputationalService computationalService;
    
    public Account createAccount(String accountName, BigDecimal initialBalance) {
        Account account = new Account();
        account.setAccountName(accountName);
        account.setBalance(initialBalance);
        Account saved = accountRepository.save(account);
        
        if (kafkaProducerService != null) {
            kafkaProducerService.sendMessage("account-created", 
                String.format("Account %d created with balance %s", saved.getAccountId(), saved.getBalance()));
        }
        
        return saved;
    }
    
    public Optional<Account> getAccount(Long accountId) {
        return accountRepository.findById(accountId);
    }
    
    public BigDecimal getBalance(Long accountId) {
        return accountRepository.findById(accountId)
            .map(Account::getBalance)
            .orElse(BigDecimal.ZERO);
    }
    
    @Transactional
    public Transaction transferMoney(Long fromAccountId, Long toAccountId, BigDecimal amount) {
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Amount must be positive");
        }
        
        // CPU-INTENSIVE: Fraud detection with cryptographic operations
        ComputationalService.FraudCheckResult fraudCheck = 
            computationalService.performFraudCheck(fromAccountId, amount);
        
        if (fraudCheck.suspicious) {
            throw new RuntimeException("Transaction flagged as suspicious by fraud detection");
        }
        
        Account fromAccount = accountRepository.findById(fromAccountId)
            .orElseThrow(() -> new RuntimeException("From account not found"));
        
        Account toAccount = accountRepository.findById(toAccountId)
            .orElseThrow(() -> new RuntimeException("To account not found"));
        
        if (fromAccount.getBalance().compareTo(amount) < 0) {
            throw new RuntimeException("Insufficient balance");
        }
        
        // CPU-INTENSIVE: Risk assessment for larger transactions
        if (amount.compareTo(BigDecimal.valueOf(1000)) > 0) {
            ComputationalService.RiskAssessment risk = 
                computationalService.calculateRiskAssessment(
                    fromAccountId, 
                    fromAccount.getBalance().doubleValue()
                );
            // Risk assessment adds CPU load but doesn't block transaction
        }
        
        fromAccount.setBalance(fromAccount.getBalance().subtract(amount));
        toAccount.setBalance(toAccount.getBalance().add(amount));
        
        accountRepository.save(fromAccount);
        accountRepository.save(toAccount);
        
        Transaction transaction = new Transaction();
        transaction.setFromAccountId(fromAccountId);
        transaction.setToAccountId(toAccountId);
        transaction.setAmount(amount);
        transaction.setTransactionType("TRANSFER");
        Transaction saved = transactionRepository.save(transaction);
        
        if (kafkaProducerService != null) {
            kafkaProducerService.sendMessage("transaction-completed",
                String.format("Transfer of %s from %d to %d (fraud score: %.2f)", 
                    amount, fromAccountId, toAccountId, fraudCheck.riskScore));
        }
        
        return saved;
    }
    
    public List<Transaction> getTransactionHistory(Long accountId) {
        return transactionRepository.findByFromAccountIdOrToAccountId(accountId, accountId);
    }
}
