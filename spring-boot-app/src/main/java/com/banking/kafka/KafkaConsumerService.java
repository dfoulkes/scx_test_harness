package com.banking.kafka;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "kafka.enabled", havingValue = "true", matchIfMissing = true)
public class KafkaConsumerService {
    
    @KafkaListener(topics = {"account-created", "transaction-completed"}, groupId = "banking-group")
    public void consumeMessage(String message) {
        // Process incoming messages
        System.out.println("Received message: " + message);
    }
}
