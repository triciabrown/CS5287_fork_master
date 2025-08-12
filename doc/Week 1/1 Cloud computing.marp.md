---
marp: true
theme: default
class: lead
paginate: true
---

## Motivating Scenario

- Suppose a bunch of entrepreneurs have just set up a small business which
  offers a new kind of internet-based service that they hope will become
  popular.
- Let’s say that hosting the service requires a good amount of computing
  power, network bandwidth, and storage requirements.
- One approach is to make resources available in-house.
- Incurs both capital expenditure (capex) and operational expenditure (opex)
- If the service is a failure or has relevance for a short duration only (e.g., selling eclipse
  glasses)—substantial losses due to capex
- If the service is highly successful—more capex to scale up, and more operational
  expenses (opex) due to maintenance, upgrades, etc.
- Even if service is successful, resources may not always be fully utilized—opex costs
  incurred for no reason (e.g., energy bills due to idling resources)

---

## Desired Solution

-
What if these entrepreneurs could lease out the resources from someone?
- We need a service model where someone provides a service that leases computing resources
-
Leasing should not mean that the resources are shipped to the entrepreneurs
- Because small businesses may not have the space and capabilities to install these resources
- Energy costs and scalability issues will still persist
- Such physical movement cannot scale up/down in a timely manner
-
Thus, the desired service model should enable
- The leased resources to be remotely accessible
- Our entrepreneurs to not be responsible for capex, opex, scalability, etc.—resources should be
  available on-demand
- A payment model that mimics traditional utilities, e.g., water, electricity


--- 
## Cloud Computing Key Properties

(Based on Berkeley Paper)
- Supports the notion of utility computing
- Pay as you go
- Service is what gets sold (or offered for a price)
- Elasticity of resources without paying a premium for the scale
- Using 1,000 servers for one hour costs no more than using one server for
  1,000 hours
- No need to pay any upfront costs and no lock-in
- Appearance of infinite computing resources available on demand
- This becomes feasible with very large data centers

---

## User Perspective of the Cloud

- Revival of the thin client on the Web
- Utility computing that charges according to metered usage
- Complex tasks which can be processed in distributed/parallel
  fashion to gain efficiency
- Power that is derived from the collection of commodity
  hardware rather than individual expensive parts


<i>Pretty much everything above is what constitutes the cloud.</i>

---

## Definition of Cloud Computing
Very hard to define, but one such definition from the National Institute for Standards and Technology has become the de facto definition
•See The [NIST Definition of Cloud Computing](http://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-145.pdf)

```
2. The NIST Definition of Cloud Computing
   Cloud computing is a model for enabling ubiquitous, convenient, on-demand network access to a shared
   pool of configurable computing resources (e.g., networks, servers, storage, applications, and services) that
   can be rapidly provisioned and released with minimal management effort or service provider interaction.
   This cloud model is composed of five essential characteristics, three service models, and four deployment
   models.
```
---

## Parsing the Definition

### Model

An abstraction for the framework or approach that serves as an enabling
technology for the following:

- Ubiquitous: accessible from anywhere, pervasive
- Convenient: should be very easy to use via any available mechanism
- On-demand: as and when needed
- Network-access: accessible over a network

---

## Parsing the Definition, Part II

- Resources: a variety of resources, e.g., CPU, storage, networks, etc.
- Shared pool: collection of resources shared across everyone who uses them;
  these are often owned by a separate entity called the cloud provider
- Configurable: ability to fine-tune these resources suited to our needs (even if
  they are part of a shared pool)
- Possible due to virtualization and isolation

## Parsing the Definition, Part III

- Rapidly provisioned/released: can be obtained almost instantaneously on demand
  and suited to our requirements or released to the pool when not needed
- Minimal management effort: no sophisticated machinery needed on the part of user
  to manage these resources
- Minimal service provider interaction: almost no need to interact with the service
  provider

---

## Five Essential Characteristics

1. On-demand self-service: ability to provision resources on-
   demand without much effort
2. Broad network access: accessible via the network through
   standard mechanisms (e.g., http) using a variety of end devices
3. Resource pooling: resources are obtained from a shared pool;
   their location and whether they are physical or virtual makes no
   difference to the user
4. Rapid elasticity: ability to scale up or down on-demand
5. Measurable service: ability to meter the usage and charged for
   whatever is being used [utility computing]

---