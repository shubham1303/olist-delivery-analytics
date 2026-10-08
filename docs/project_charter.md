# Project Charter

## Working title

Olist Delivery & Customer Experience Analytics

## Business scenario

The Director of Marketplace Operations needs a trustworthy operational view of
fulfillment performance. Leadership can see completed orders, but it lacks a
consistent method for determining which sellers, product categories, and regions
are associated with late delivery and poor customer reviews.

## Problem statement

Late orders can harm customer satisfaction and repeat purchasing. Olist needs a
reproducible analytics system that distinguishes seller-handling delay from
carrier-transit delay, measures the effect of delivery performance on review
scores, and helps operations teams prioritize high-impact interventions.

## Project objective

Design and implement a SQL Server and Power BI solution that:

1. integrates the nine Olist source files at their correct grains;
2. makes data-quality and metric assumptions visible;
3. monitors delivery, customer-experience, and commercial KPIs;
4. identifies material operational problem areas; and
5. supports decisions at seller, category, state, and monthly levels.

## Primary stakeholder

Director of Marketplace Operations

## Secondary users

- Seller Success Manager
- Logistics Operations Manager
- Customer Experience Manager
- Business Intelligence Analyst

## Decisions the solution should support

- Which sellers should receive fulfillment coaching or closer monitoring?
- Which categories and customer states have the largest late-order exposure?
- Is delay concentrated before carrier handoff or during carrier transit?
- How strongly is late delivery associated with one- and two-star reviews?
- Where can an intervention protect the most order value and customers?

## Core business questions

1. What share of delivered orders arrive after the estimated delivery date?
2. How do handling time and carrier-transit time contribute to total delivery time?
3. Which sellers, categories, and states combine high volume with poor delivery performance?
4. How do review scores differ for early, on-time, and late deliveries?
5. How are GMV, freight, order volume, and cancellations changing over time?
6. What proportion of known customers place more than one delivered order?

## Version 1 scope

- source-data profiling and documented quality rules;
- SQL Server staging and analytics schemas;
- reusable SQL views for governed KPIs;
- a Power BI semantic model;
- three dashboard pages;
- insight and recommendation documentation; and
- a polished GitHub README with screenshots and architecture.

## Out of scope for version 1

- machine-learning predictions;
- natural-language sentiment modeling;
- real-time streaming or orchestration;
- production cloud deployment;
- marketing-funnel data outside the nine-file dataset; and
- causal claims about delivery delays and review scores.

## Success criteria

- All nine sources load successfully with documented row counts.
- Required keys and relationships are tested before modeling.
- Monetary totals are protected from many-to-many row multiplication.
- Every displayed KPI has a written definition, grain, filter, and limitation.
- Dashboard filters reconcile to SQL control totals.
- Findings lead to at least three specific, evidence-backed operational actions.

## Important assumptions and limitations

- The dataset is historical (2016–2018), so recommendations demonstrate analytical
  reasoning rather than describe Olist's current operations.
- Association between late delivery and low ratings does not prove causation.
- Orders can contain multiple items fulfilled by different sellers.
- Orders can contain multiple payment records.
- Customer-level retention uses `customer_unique_id`; `customer_id` represents an
  order-linked customer record and must not be used to identify repeat customers.
- Revenue terminology must be explicit. Version 1 uses item price as GMV and
  reports freight separately.
