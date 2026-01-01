---
name: implement-feature
description: |
  Guide for implementing features in ClaudeBar following architecture-first design, TDD, rich domain models, and Swift 6.2 patterns. Use this skill when:
  (1) Adding new functionality to the app
  (2) Creating domain models that follow user's mental model
  (3) Building SwiftUI views that consume domain models directly
  (4) User asks "how do I implement X" or "add feature Y"
  (5) Implementing any feature that spans Domain, Infrastructure, and App layers
---

# Implement Feature in ClaudeBar

Implement features using architecture-first design, TDD, rich domain models, and Swift 6.2 patterns.

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────┐
│  1. ARCHITECTURE DESIGN (Required - User Approval Needed)  │
├─────────────────────────────────────────────────────────────┤
│  • Analyze requirements                                     │
│  • Create component diagram                                 │
│  • Show data flow and interactions                          │
│  • Present to user for review                               │
│  • Wait for approval before proceeding                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ (User Approves)
┌─────────────────────────────────────────────────────────────┐
│  2. TDD IMPLEMENTATION                                      │
├─────────────────────────────────────────────────────────────┤
│  • Domain model tests → Domain models                       │
│  • Infrastructure tests → Implementations                   │
│  • Integration and views                                    │
└─────────────────────────────────────────────────────────────┘
```

## Phase 0: Architecture Design (MANDATORY)

Before writing any code, create an architecture diagram and get user approval.

### Step 1: Analyze Requirements

Identify:
- What new models/types are needed
- Which existing components will be modified
- Data flow between components
- External dependencies (CLI, API, etc.)

### Step 2: Create Architecture Diagram

Use ASCII diagram showing all components and their interactions:

```
Example: Adding a new AI provider

┌─────────────────────────────────────────────────────────────────────┐
│                           ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐  │
│  │  External   │     │  Infrastructure  │     │     Domain       │  │
│  └─────────────┘     └──────────────────┘     └──────────────────┘  │
│                                                                      │
│  ┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐  │
│  │  CLI Tool   │────▶│  NewUsageProbe   │────▶│  UsageSnapshot   │  │
│  │  (new-cli)  │     │  (implements     │     │  (existing)      │  │
│  └─────────────┘     │   UsageProbe)    │     └──────────────────┘  │
│                      └──────────────────┘              │             │
│                              │                         ▼             │
│                              │              ┌──────────────────┐     │
│                              │              │  NewProvider     │     │
│                              └─────────────▶│  (AIProvider)    │     │
│                                             └──────────────────┘     │
│                                                       │              │
│                                                       ▼              │
│                              ┌──────────────────────────────────┐   │
│                              │  App Layer                        │   │
│                              │  ┌────────────────────────────┐   │   │
│                              │  │ ClaudeBarApp.swift         │   │   │
│                              │  │ (register new provider)    │   │   │
│                              │  └────────────────────────────┘   │   │
│                              └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Step 3: Document Component Interactions

List each component with:
- **Purpose**: What it does
- **Inputs**: What it receives
- **Outputs**: What it produces
- **Dependencies**: What it needs

```
Example:

| Component      | Purpose                | Inputs          | Outputs        | Dependencies    |
|----------------|------------------------|-----------------|----------------|-----------------|
| NewUsageProbe  | Fetch usage from CLI   | CLI command     | UsageSnapshot  | CLIExecutor     |
| NewProvider    | Manages probe lifecycle| UsageProbe      | snapshot state | UsageProbe      |
```

### Step 4: Present for User Approval

**IMPORTANT**: Always ask user to review the architecture before implementing.

Use AskUserQuestion tool with options:
- "Approve - proceed with implementation"
- "Modify - I have feedback on the design"

Do NOT proceed to Phase 1 until user explicitly approves.

---

## Core Principles

### 1. Rich Domain Models (User's Mental Model)

Domain models encapsulate behavior, not just data:

```swift
// Rich domain model with behavior
public struct UsageQuota: Sendable, Equatable {
    public let percentRemaining: Double

    // Domain behavior - computed from state
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    public var isDepleted: Bool { percentRemaining <= 0 }
    public var needsAttention: Bool { status.needsAttention }
}
```

### 2. Swift 6.2 Patterns (No ViewModel Layer)

Use `@Observable` classes with views consuming domain models directly:

```swift
@Observable
final class AppState {
    var providers: [any AIProvider] = []
    var overallStatus: QuotaStatus {
        providers.compactMap(\.snapshot?.overallStatus).max() ?? .healthy
    }
}

struct ProviderSectionView: View {
    let snapshot: UsageSnapshot  // Domain model directly

    var body: some View {
        Text(snapshot.overallStatus.displayName)
    }
}
```

### 3. Protocol-Based DI with @Mockable

```swift
@Mockable
public protocol UsageProbe: Sendable {
    func probe() async throws -> UsageSnapshot
    func isAvailable() async -> Bool
}
```

## Architecture

```
Domain (Sources/Domain/)
├── Rich models with behavior
├── Protocols defining capabilities
└── Actors for thread-safe services

Infrastructure (Sources/Infrastructure/)
├── Protocol implementations
├── CLI probes, network clients
└── Adapters (excluded from coverage)

App (Sources/App/)
├── Views with domain models
├── @Observable AppState
└── No ViewModel layer
```

## TDD Workflow

### Phase 1: Domain Model Tests

```swift
@Suite
struct FeatureModelTests {
    @Test func `model computes status from state`() {
        let model = FeatureModel(value: 50)
        #expect(model.status == .normal)
    }
}
```

### Phase 2: Infrastructure Tests

```swift
@Suite
struct FeatureServiceTests {
    @Test func `service returns data on success`() async throws {
        let mockClient = MockNetworkClient()
        given(mockClient).fetch(...).willReturn(Data())

        let service = FeatureService(client: mockClient)
        let result = try await service.fetch()

        #expect(result != nil)
    }
}
```

### Phase 3: Integration

Wire up in `ClaudeBarApp.swift` and create views.

## References

- [Architecture diagram patterns](references/architecture-diagrams.md) - ASCII diagram examples for different scenarios
- [Swift 6.2 @Observable patterns](references/swift-observable.md)
- [Rich domain model patterns](references/domain-models.md)
- [TDD test patterns](references/tdd-patterns.md)

## Checklist

### Architecture Design (Phase 0)
- [ ] Analyze requirements and identify components
- [ ] Create ASCII architecture diagram with component interactions
- [ ] Document component table (purpose, inputs, outputs, dependencies)
- [ ] **Get user approval before proceeding**

### Implementation (Phases 1-3)
- [ ] Define domain models in `Sources/Domain/` with behavior
- [ ] Write domain model tests (test behavior, not data)
- [ ] Define protocols with `@Mockable`
- [ ] Implement infrastructure in `Sources/Infrastructure/`
- [ ] Write infrastructure tests with mocks
- [ ] Create views consuming domain models directly
- [ ] Use `@Observable` for shared state
- [ ] Run `swift test` to verify all tests pass