"""Router package.

Submodules are imported explicitly where they are used (``app.main`` does
``from app.routers import auth, categories, ...``), and Python imports a
submodule on demand for that form. Listing them here too would only create
unused imports, so this file exists for package identity only.
"""
