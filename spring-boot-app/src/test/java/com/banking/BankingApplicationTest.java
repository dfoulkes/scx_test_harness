package com.banking;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@ActiveProfiles("test")
class BankingApplicationTest {

    @Autowired
    private ApplicationContext applicationContext;

    @Test
    void contextLoads() {
        assertNotNull(applicationContext);
        System.out.println("Spring Boot application context loaded successfully");
    }

    @Test
    void testAllBeansLoaded() {
        assertNotNull(applicationContext.getBean("bankingService"));
        assertNotNull(applicationContext.getBean("computationalService"));
        assertNotNull(applicationContext.getBean("bankingController"));
        
        System.out.println("All required beans loaded successfully");
    }
}
