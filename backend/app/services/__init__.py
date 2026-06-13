"""Service layer — pure business logic, no FastAPI dependency.

Each service encapsulates a domain (KPR, credit cards, transactions, etc.)
and is instantiated with the data repositories it needs.

Services should NOT:
- Import FastAPI (HTTPException, Depends, Request, etc.)
- Handle HTTP concerns (status codes, response models)
- Access request objects
"""
