# AI chat rolling summary + full debt context

> One rolling summary (not vector memory). Per-KPR / per-card debt snapshot is injected into the system prompt.

## 1. Problem

- The model only saw the last ~10 turns. Older context disappeared.
- Sending the full thread wastes tokens.
- The debt block was totals + names only — no installment, remaining principal, rate, or schedule.

## 2. Rolling summary

- Table `ai_chat_summaries` (one row per user): `summary`, `covered_through_id`.
- Raw window: last **12 complete messages** (~6 turns).
- Older messages fold into one summary (Flash, ~800 tokens max).
- Model payload: money snapshot + summary + window + new question.
- Re-summarize only when new complete messages fall out of the window (not per token).
- Summary content: decisions, preferences, constraints, open threads. **Do not** repeat numbers (those live in the snapshot).
- Clear chat / delete account → delete the summary.

## 3. Debt context

Per KPR: name, owner, property price, down payment, loan, type+rate, tenor, start, due day, current installment, remaining principal, extra payments.

Per card: name, owner, limit, billing/due day, spend this month, each active installment (description, monthly amount, remaining months).

Figures come from the DB, not a 9% client estimate.

## 4. Out of scope

- Vector / embedding memory
- Chat UI changes
- Summarizing on the APK
