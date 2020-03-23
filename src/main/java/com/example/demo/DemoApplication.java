package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication(proxyBeanMethods = false)
public class DemoApplication {

	public static void main(String[] args) {
		SpringApplication.run(DemoApplication.class, args);
	}

}

@RestController
class JunkHealthIndicator implements HealthIndicator {

	private static Health OUT_OF_SERVICE = Health.outOfService().build();
	private static Health OK = Health.up().build();

	private Health status = OK;

	@Override
	public Health health() {
		return status;
	}

	@PostMapping("/die")
	public String die() {
		status = OUT_OF_SERVICE;
		return "Switched to OUT_OF_SERVICE";
	}

	@PostMapping("/live")
	public String live() {
		status = OK;
		return "Switched to OK";
	}

}
