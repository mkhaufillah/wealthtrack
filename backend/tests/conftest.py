TEST_DB_URL = os.getenv(
    "WEALTHTRACK_TEST_DATABASE_URL",
    "postgresql://wealthtrack_test:***@localhost:5432/wealthtrack_test",
)