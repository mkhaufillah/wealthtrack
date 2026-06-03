# Admin Category CRUD — Implementation Plan

> **For Hermes:** Execute this plan task-by-task using subagent-driven-development.

**Goal:** Add admin-only category management (create + edit) across all layers — backend API, Flutter admin screen, Hermes cron skill. Categories become fully dynamic, no more hardcoded keyword maps or translation tables.

**Architecture:** New DB columns on `categories` table (`name_en`, `keywords`). Backend adds POST + PUT endpoints with admin role guard. Hermes `classify_transaction()` reads keywords from DB instead of hardcoded dicts. Flutter replaces `category_translator.dart` with direct `name_en` field from API. New admin screen for managing categories.

**Tech Stack:** FastAPI + PostgreSQL + Flutter + Hermes (Python)

**Principle:** CREATE + EDIT only, **no DELETE.** Categories referenced by transactions/budgets cannot be safely removed. Soft-deactivate if needed later.

---

## Pre-Flight: What Exists

| Layer | Current state |
|-------|---------------|
| `categories` table | `id`, `name`, `type`, `icon`, `is_default`, `sort_order` |
| Backend `GET /categories` | Returns all, optional `?type=` filter |
| Backend `GET /transactions` | Validates `category_id` exists in DB |
| Backend `POST /transactions` | Fetches category by id, 404 if missing |
| Backend budgets | `LEFT JOIN categories` — orphan-safe |
| Backend OCR | `_load_categories()` fetches from DB dynamically |
| Hermes `finance_db.py` | Hardcoded `EXPENSE_KEYWORDS` / `INCOME_KEYWORDS` dicts + `classify_transaction()` |
| Flutter `category_translator.dart` | Hardcoded `Map<String, String>` for ID→EN translation |
| Flutter `CategoryPicker` | Loads categories from API dynamically |
| Flutter `BudgetsScreen` | Uses `category_id` from budgets — dynamic |

---

## Migration: `categories` Table

Add two columns:

```sql
ALTER TABLE categories ADD COLUMN name_en TEXT DEFAULT '';
ALTER TABLE categories ADD COLUMN keywords TEXT DEFAULT '[]';
```

Backfill existing categories with English names and keyword JSON:

| name (ID) | name_en | keywords (JSON array) |
|-----------|---------|----------------------|
| Gaji | Salary | ["gaji", "salary", "payroll", "thr"] |
| Freelance | Freelance | ["freelance", "project", "honor", "jasa"] |
| Bonus & THR | Bonus & THR | ["bonus", "insentif", "thr", "tunjangan"] |
| Investasi | Investment | ["dividen", "capital gain", "profit", "bunga"] |
| Lainnya (income) | Other | ["refund", "hadiah", "reimbursement"] |
| Makanan & Minuman | Food & Drinks | ["makan", "minum", "kopi", "nasi", "mie", ...] |
| Transportasi & Bensin | Transport & Fuel | ["bensin", "bbm", "toll", "tol", "parkir", ...] |
| Belanja Harian | Daily Shopping | ["belanja", "alfamart", "indomaret", "sabun", ...] |
| Hiburan | Entertainment | ["nonton", "bioskop", "netflix", "spotify", ...] |
| Tagihan & Cicilan | Bills & Installments | ["listrik", "pln", "pdam", "air", ...] |
| Kesehatan | Health | ["obat", "apotek", "klinik", "vitamin", ...] |
| Pendidikan | Education | ["kursus", "les", "buku", "sekolah", ...] |
| Tabungan & Investasi (expense) | Savings & Investment | ["tabungan", "deposito", "rekening", "emas", ...] |
| Kebutuhan Bayi/Anak | Baby & Child Needs | ["bayi", "popok", "susu bayi", "mpasi", ...] |
| Lainnya (expense) | Other | [] |
| Transfer (expense) | Transfer | ["transfer ke", "transfer untuk"] |
| Transfer (income) | Transfer | ["transfer dari"] |

---

## Tasks

### Part 1: DB Migration

#### Task 1.1: Add migration script for new columns

**Objective:** Add `name_en` and `keywords` columns to `categories` table, backfill with seed data.

**Files:**
- Modify: `backend/app/migrate_db.py`

**Code to add** at end of `run_migration()` function, after existing migrations:

```python
# 7. Add name_en + keywords to categories
cat_cols = [row[1] for row in conn.execute("PRAGMA table_info(categories)").fetchall()]
if 'name_en' not in cat_cols:
    conn.execute("ALTER TABLE categories ADD COLUMN name_en TEXT DEFAULT ''")
if 'keywords' not in cat_cols:
    conn.execute("ALTER TABLE categories ADD COLUMN keywords TEXT DEFAULT '[]'")

# Backfill name_en + keywords for existing categories
CATEGORY_BACKFILL = {
    "Gaji": {"name_en": "Salary", "keywords": json.dumps(["gaji", "salary", "payroll", "thr", "gaji bulan"])},
    "Freelance": {"name_en": "Freelance", "keywords": json.dumps(["freelance", "project", "proyek", "honor", "jasa", "konsultan"])},
    "Bonus & THR": {"name_en": "Bonus & THR", "keywords": json.dumps(["bonus", "insentif", "reward", "thr", "tunjangan", "bonus tahunan"])},
    "Investasi": {"name_en": "Investment", "keywords": json.dumps(["dividen", "capital gain", "profit", "bunga", "interest", "return investasi"])},
    # Income Lainnya
    "Lainnya": {"name_en": "Other", "keywords": json.dumps(["transfer masuk", "refund", "hadiah", "reimbursement", "reimburse"])},
    "Makanan & Minuman": {"name_en": "Food & Drinks", "keywords": json.dumps([...])},
    "Transportasi & Bensin": {"name_en": "Transport & Fuel", "keywords": json.dumps([...])},
    "Belanja Harian": {"name_en": "Daily Shopping", "keywords": json.dumps([...])},
    "Hiburan": {"name_en": "Entertainment", "keywords": json.dumps([...])},
    "Tagihan & Cicilan": {"name_en": "Bills & Installments", "keywords": json.dumps([...])},
    "Kesehatan": {"name_en": "Health", "keywords": json.dumps([...])},
    "Pendidikan": {"name_en": "Education", "keywords": json.dumps([...])},
    "Tabungan & Investasi": {"name_en": "Savings & Investment", "keywords": json.dumps([...])},
    "Kebutuhan Bayi/Anak": {"name_en": "Baby & Child Needs", "keywords": json.dumps([...])},
    "Transfer": {"name_en": "Transfer", "keywords": json.dumps(["transfer ke", "transfer untuk"])},
}

for cat_name, data in CATEGORY_BACKFILL.items():
    conn.execute(
        "UPDATE categories SET name_en = ?, keywords = ? WHERE name = ? AND (name_en IS NULL OR name_en = '')",
        (data["name_en"], data["keywords"], cat_name),
    )
```

**Note:** The `...` for keyword arrays should copy the full lists from `finance_db.py` line 51-123.

**Edge case:** `Lainnya` appears for both expense and income. The update handles both rows since `WHERE name = ? AND name_en IS NULL` catches both.

**Verify:**
```bash
# Check categories via API
curl -s -H "Authorization: Bearer YOUR_TOKEN" https://wealthtrack.filla.id/api/v1/categories | python3 -m json.tool
```

---

### Part 2: Backend API

#### Task 2.1: Add schemas for create/update

**Objective:** Pydantic models for category CRUD requests.

**Files:**
- Modify: `backend/app/schemas/category.py`

```python
class CategoryCreate(BaseModel):
    name: str
    name_en: str = ""
    type: Literal["expense", "income"]
    icon: str = ""
    keywords: list[str] = []
    sort_order: int = 0

class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    name_en: Optional[str] = None
    icon: Optional[str] = None
    keywords: Optional[list[str]] = None
    sort_order: Optional[int] = None
```

Add `name_en` and `keywords` to `CategoryOut`:
```python
class CategoryOut(BaseModel):
    id: int
    name: str
    name_en: str = ""
    type: str
    icon: str
    is_default: bool
    keywords: list[str] = []
```

**Note:** Add `from typing import Literal` and expand `Optional` imports.

#### Task 2.2: Add POST /categories endpoint

**Objective:** Create a new category. Admin only.

**Files:**
- Modify: `backend/app/routers/categories.py`

```python
@router.post("", status_code=201)
@limiter.limit("30/minute")
async def create_category(
    request: Request,
    data: CategoryCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only admin can create categories")

    cursor = await db.execute(
        "SELECT id FROM categories WHERE name = ? AND type = ?",
        (data.name, data.type),
    )
    if await cursor.fetchone():
        raise HTTPException(status_code=409, detail=f"Category '{data.name}' already exists for type '{data.type}'")

    keywords_json = json.dumps(data.keywords) if data.keywords else "[]"
    cursor = await db.execute(
        """INSERT INTO categories (name, name_en, type, icon, keywords, sort_order)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (data.name, data.name_en, data.type, data.icon, keywords_json, data.sort_order),
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE id = ?",
        (cursor.lastrowid,),
    )
    row = await cursor.fetchone()
    return _format_category(row)
```

Helper function to format category response:
```python
def _format_category(row) -> dict:
    kw = row["keywords"]
    return dict(row) | {"keywords": json.loads(kw) if kw else []}
```

#### Task 2.3: Add PUT /categories/{id} endpoint

**Objective:** Edit an existing category. Admin only. No DELETE.

**Files:**
- Modify: `backend/app/routers/categories.py`

```python
@router.put("/{category_id}")
@limiter.limit("30/minute")
async def update_category(
    request: Request,
    category_id: int,
    data: CategoryUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only admin can update categories")

    # Check exists
    cursor = await db.execute(
        "SELECT id, name, type, is_default FROM categories WHERE id = ?", (category_id,)
    )
    existing = await cursor.fetchone()
    if not existing:
        raise HTTPException(status_code=404, detail="Category not found")

    # Check name uniqueness if renaming
    if data.name is not None and data.name != existing["name"]:
        cursor = await db.execute(
            "SELECT id FROM categories WHERE name = ? AND type = ? AND id != ?",
            (data.name, existing["type"], category_id),
        )
        if await cursor.fetchone():
            raise HTTPException(status_code=409, detail="Category name already exists")

    updates = {}
    if data.name is not None:
        updates["name"] = data.name
    if data.name_en is not None:
        updates["name_en"] = data.name_en
    if data.icon is not None:
        updates["icon"] = data.icon
    if data.keywords is not None:
        updates["keywords"] = json.dumps(data.keywords)
    if data.sort_order is not None:
        updates["sort_order"] = data.sort_order

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = ?" for k in updates)
    await db.execute(
        f"UPDATE categories SET {set_clause} WHERE id = ?",
        list(updates.values()) + [category_id],
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE id = ?",
        (category_id,),
    )
    return _format_category(await cursor.fetchone())
```

#### Task 2.4: Update GET /categories to return name_en + keywords

**Objective:** Modify existing list endpoint to include new fields.

**Files:**
- Modify: `backend/app/routers/categories.py`

Update query from:
```python
"SELECT id, name, type, icon, is_default FROM categories WHERE type = ? ORDER BY sort_order"
```
to:
```python
"SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE type = ? ORDER BY sort_order"
```

And format each row through `_format_category()` instead of `dict(r)`.

#### Task 2.5: Backend tests

**Objective:** Test new endpoints.

**Files:**
- Modify: `backend/tests/test_categories.py` (or create)

Test cases:
1. `admin_can_create_category` — filla creates "Test" category
2. `non_admin_cannot_create` — nahda gets 403
3. `duplicate_name_returns_409`
4. `admin_can_update_category` — rename, change icon
5. `non_admin_cannot_update`
6. `update_nonexistent_returns_404`
7. `list_returns_name_en_and_keywords`

---

### Part 3: Flutter — Translation Dynamic

#### Task 3.1: Update CategoryChip to carry name_en

**Objective:** `CategoryChip` class needs to carry the English name from API.

**Files:**
- Modify: `mobile/lib/features/transactions/ui/widgets/category_picker.dart`

```dart
class CategoryChip {
  final int id;
  final String name;
  final String nameEn;
  final String icon;
  const CategoryChip({
    required this.id,
    required this.name,
    this.nameEn = '',
    required this.icon,
  });
}
```

Update the label in `CategoryPicker`:
```dart
label: Text('${cat.icon} ${cat.nameEn.isNotEmpty ? cat.nameEn : translateCategory(cat.name)}'),
```

This way: if `name_en` exists (from new categories), use it. Otherwise fallback to old translation map (for backward compat until migration runs).

#### Task 3.2: Update add_transaction_screen to load name_en

**Objective:** When fetching categories, parse the new field.

**Files:**
- Modify: `mobile/lib/features/transactions/ui/add_transaction_screen.dart`

Update `_loadAllCategories()`:
```dart
_expenseCategories = (List<Map<String, dynamic>>.from(expenseRes.data)).map((e) => CategoryChip(
  id: e['id'] as int,
  name: e['name'] as String,
  nameEn: e['name_en'] as String? ?? '',
  icon: e['icon'] as String? ?? '📦',
)).toList();
```

(Same for `_incomeCategories`.)

#### Task 3.3: Admin Category List Screen

**Objective:** New screen to list, add, and edit categories. Only accessible by admin.

**Files:**
- Create: `mobile/lib/features/categories/ui/category_management_screen.dart`
- Modify: `mobile/lib/features/profile/ui/profile_screen.dart` (add nav entry)

**Screen structure:**
- AppBar: "Manage Categories"
- FAB: Add new category
- List: each row shows icon + name + name_en + type, tap to edit
- Add/Edit: bottom sheet with fields:
  - Name (ID) — required
  - Name (EN) — required
  - Type — dropdown (expense/income), readonly on edit
  - Icon — emoji text field
  - Keywords — comma-separated text field
  - Sort Order — number field

**Guard:** Show nav entry only if `authProvider.user?.role == 'admin'`.

---

### Part 4: Hermes Skill — Dynamic Keywords

#### Task 4.1: Update finance_db.py — remove hardcoded keyword dicts

**Objective:** Replace `EXPENSE_KEYWORDS` and `INCOME_KEYWORDS` dicts with DB query.

**Files:**
- Modify: `~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py`

Remove lines 51-123 (the two dicts).

Add function:
```python
def load_keywords_from_db():
    """Load category→keywords mapping from categories table."""
    conn = get_conn()
    cursor = conn.execute(
        "SELECT name, type, keywords FROM categories WHERE keywords IS NOT NULL AND keywords != '[]'"
    )
    rows = cursor.fetchall()
    conn.close()
    expense = {}
    income = {}
    for r in rows:
        kw_list = json.loads(r["keywords"]) if r["keywords"] else []
        if r["type"] == "expense":
            expense[r["name"]] = kw_list
        else:
            income[r["name"]] = kw_list
    return expense, income
```

Update `classify_transaction()`:
```python
def classify_transaction(description, tx_type):
    """Classify transaction description into a category based on keywords from DB."""
    desc_lower = description.lower()
    expense_keywords, income_keywords = load_keywords_from_db()
    keywords = expense_keywords if tx_type == "expense" else income_keywords

    for category, kw_list in keywords.items():
        for keyword in kw_list:
            if keyword.lower() in desc_lower:
                return category
    return "Lainnya"  # fallback
```

#### Task 4.2: Update get_category_id — remove auto-create

**Objective:** Remove auto-INSERT behavior for unknown categories. Fallback to "Lainnya" instead.

**Files:**
- Modify: `~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py`

Update `get_category_id()`:
```python
def get_category_id(name, tx_type):
    """Get category ID by name and type. Returns Lainnya if not found."""
    conn = get_conn()
    cursor = conn.execute(
        "SELECT id FROM categories WHERE name = ? AND type = ?",
        (name, tx_type),
    )
    row = cursor.fetchone()
    conn.close()
    if row:
        return row["id"]
    # Fallback to Lainnya
    cursor.execute(
        "SELECT id FROM categories WHERE name = 'Lainnya' AND type = ?",
        (tx_type,),
    )
    row = cursor.fetchone()
    return row["id"] if row else None
```

---

### Part 5: Flutter — Admin Screen

(Tasks 3.1-3.3 cover the admin screen. This part adds the full implementation details.)

#### Task 5.1: Category Management Screen

**Objective:** Build `CategoryManagementScreen` with list, add, edit.

**Files:**
- Create: `mobile/lib/features/categories/providers/category_provider.dart`
- Create: `mobile/lib/features/categories/ui/category_management_screen.dart`

**Provider:**
```dart
class CategoryManagementNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final ApiClient _api;
  CategoryManagementNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      final res = await _api.get('/categories');
      state = AsyncValue.data(List<Map<String, dynamic>>.from(res.data));
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<bool> create(Map<String, dynamic> data) async { ... }
  Future<bool> update(int id, Map<String, dynamic> data) async { ... }
}
```

**Screen:** ListView with categories grouped by type (expense / income). Each item shows icon, name, name_en. Tap to edit. FAB to add.

**Navigation:** Add entry in Profile screen (or Settings), gated by `role == 'admin'`.

---

### Part 6: Sync Docs

#### Task 6.1: Create feature doc

**Objective:** Document what was built.

**Files:**
- Create: `docs/17-admin-category-crud.md`

Cover: architecture (data flow), migration details, new endpoints, Flutter screen, Hermes skill changes, files changed.

#### Task 6.2: Update existing docs

**Files:**
- `README.md` — add 17 to listing
- `docs/01-project-overview.md` — add link
- `docs/03-backend-api.md` — add new category endpoints to API spec
- `docs/16-ocr-scanner.md` — note that OCR uses dynamic categories from DB (already did, but confirm)

---

## Summary of All Changes

| Layer | Files | Change |
|-------|-------|--------|
| DB | `migrate_db.py` | Add `name_en`, `keywords` columns + backfill |
| Backend | `schemas/category.py` | Add CategoryCreate, CategoryUpdate, update CategoryOut |
| Backend | `routers/categories.py` | Add POST + PUT, return name_en + keywords in list |
| Backend | `routers/categories.py` | Add `_format_category()` helper |
| Backend | `tests/test_categories.py` | Add tests for create + update + auth |
| Flutter | `widgets/category_picker.dart` | Add `nameEn` field to CategoryChip |
| Flutter | `add_transaction_screen.dart` | Parse `name_en` from API response |
| Flutter | `category_management_screen.dart` | **NEW** — admin list/add/edit |
| Flutter | `category_provider.dart` | **NEW** — category management provider |
| Flutter | `profile_screen.dart` | Add nav entry for admin |
| Flutter | `app_router.dart` | Add route for management screen |
| Hermes | `finance_db.py` | Replace hardcoded keyword dicts with DB query |
| Hermes | `finance_db.py` | Remove auto-create from `get_category_id()` |
| Docs | `docs/17-admin-category-crud.md` | **NEW** feature doc |
| Docs | `README.md`, `01-project-overview.md`, `03-backend-api.md` | Update cross-refs |

## Verification

After all tasks:
1. Run backend tests: `pytest backend/tests/ -v` → 170+ passed
2. Run Flutter tests: `flutter test` → 240+ passed
3. Manually test: admin creates "Kendaraan" category with name_en "Vehicle" → shows in app with English name
4. Hermes: run `python3 finance_db.py add-transaction expense 10000 "bensin pertalite"` → categorized as "Transportasi & Bensin"
5. Hermes with unknown keyword: run with "jasa cleaning service" → falls back to "Lainnya"
