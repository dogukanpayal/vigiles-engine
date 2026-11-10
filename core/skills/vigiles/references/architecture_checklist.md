# Veteran Architecture & Engineering Checklist

Use this checklist during Phase 2 of the Veteran Engineering Protocol to review designs and detect pitfalls before writing code.

---

## 1. Data & Persistence
- [ ] **Transactions**: Are multi-step database writes wrapped in atomic transactions?
- [ ] **Indexes**: Are foreign keys and query filter columns properly indexed?
- [ ] **N+1 Prevention**: Are ORM relationships eagerly loaded where needed?
- [ ] **Idempotency**: Can write operations (payments, webhooks, state transitions) safely run multiple times without duplicating data?

## 2. API & Contract Integrity
- [ ] **Backwards Compatibility**: Do changes break existing clients or consumers?
- [ ] **Validation**: Are all user/external inputs strictly validated at the controller/handler boundary?
- [ ] **Error Contracts**: Are error responses uniform, typed, and devoid of internal stack trace leaks?

## 3. Resilience & Concurrency
- [ ] **Race Conditions**: Are shared state access points protected (mutex, distributed locks, database row locks)?
- [ ] **Timeouts & Deadlines**: Do all external HTTP calls and DB connections have explicit timeout values?
- [ ] **Graceful Degradation**: If an external dependency or service is unreachable, does the system fail safely?

## 4. Testability & Maintainability
- [ ] **Determinism**: Are tests free from sleep statements, flaky network dependencies, or time-of-day assumptions?
- [ ] **Separation of Concerns**: Is business logic decoupled from transport/framework code (controllers, routes)?
- [ ] **Observability**: Are errors logged with sufficient context (IDs, operation names) for future debugging?
